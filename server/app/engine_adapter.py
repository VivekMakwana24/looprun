"""The ONLY module that imports looprun_engine.

The rest of the server talks to the engine through the plain functions and dataclasses below, so the
engine can be replaced (tests inject a fake with `set_engine`) without touching routes or workers.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import h3

_engine: Any = None

# Soft engine flags that the server treats as 'hold until a human has looked' (decision: implausible loops).
HOLD_SOFT_CODES = frozenset({"implausible_loop"})


def set_engine(module: Any | None) -> None:
    """Inject an engine implementation (module-like object with the ENGINE_SPEC API). None resets."""
    global _engine
    _engine = module


def engine() -> Any:
    global _engine
    if _engine is None:
        import looprun_engine  # noqa: PLC0415 - lazy so the server imports without the engine installed

        _engine = looprun_engine
    return _engine


@dataclass(frozen=True)
class ProcessedRun:
    distance_m: float
    moving_seconds: int
    loops: list[dict] = field(default_factory=list)  # [{"cells": int, "area_km2": float}]
    flags: list[dict] = field(default_factory=list)  # [{"code","severity","detail"}]
    cells: list[str] = field(default_factory=list)

    @property
    def on_hold(self) -> bool:
        """Hard flags, and the soft flags in HOLD_SOFT_CODES, hold the run for review: no cells, pending_review."""
        return any(f["severity"] == "hard" or f["code"] in HOLD_SOFT_CODES for f in self.flags)

    @property
    def status(self) -> str:
        return "pending_review" if self.on_hold else "accepted"


def process_run(fixes: list[list]) -> ProcessedRun:
    """fixes: [[lat, lng, t_ms, acc, mock], ...]"""
    e = engine()
    result = e.process_run([e.Fix(lat=f[0], lng=f[1], t=int(f[2]), acc=float(f[3]), mock=bool(f[4])) for f in fixes])
    flags = [{"code": f.code, "severity": f.severity, "detail": f.detail} for f in result.flags]
    hold = any(f["severity"] == "hard" or f["code"] in HOLD_SOFT_CODES for f in flags)
    return ProcessedRun(
        distance_m=float(result.distance_m),
        moving_seconds=int(result.moving_seconds),
        loops=[{"cells": len(lp.cells), "area_km2": float(lp.area_km2)} for lp in result.loops],
        flags=flags,
        # Held runs award no cells, whatever the engine returned.
        cells=[] if hold else sorted(set(result.cells)),
    )


def effort_credit(moving_seconds: int, n_cells: int) -> float:
    return float(engine().effort_credit(moving_seconds, n_cells))


def faded_power(user_id: str, power: float, updated_at: int, now: int, freeze_until: int | None) -> float:
    e = engine()
    return float(
        e.faded_power(e.CellPower(user_id=user_id, power=power, updated_at=updated_at), now, freeze_until=freeze_until)
    )


@dataclass(frozen=True)
class ClaimOutcome:
    powers: dict[str, tuple[float, int]]  # user_id -> (stored power, updated_at)
    old_owner: str | None
    new_owner: str | None

    @property
    def changed(self) -> bool:
        return self.old_owner != self.new_owner


def apply_claim(
    cell: str,
    powers: dict[str, tuple[float, int]],
    current_owner: str | None,
    user_id: str,
    credit: float,
    now: int,
    freezes: dict[str, int] | None = None,
) -> ClaimOutcome:
    e = engine()
    pw = {u: e.CellPower(user_id=u, power=p, updated_at=t) for u, (p, t) in powers.items()}
    new_powers, change = e.apply_claim(cell, pw, current_owner, user_id, credit, now, freezes=freezes or None)
    out = {u: (float(cp.power), int(cp.updated_at)) for u, cp in new_powers.items()}
    new_owner = change.new_owner if change is not None else current_owner
    return ClaimOutcome(powers=out, old_owner=current_owner, new_owner=new_owner)


def cell_centre(cell: str) -> tuple[float, float]:
    return tuple(engine().cell_centre(cell))  # type: ignore[return-value]


def in_home_zone(cell: str, zones: list[tuple[float, float, float]]) -> bool:
    return bool(zones) and bool(engine().in_home_zone(cell, zones))


def grid_disk(cell: str, k: int) -> list[str]:
    return list(h3.grid_disk(cell, k))


def grace_days() -> float:
    return float(engine().Config().grace_days)


def validate_config() -> None:
    """Refuse to start with nonsense engine tunables (the engine does not guard against them)."""
    cfg = engine().Config()
    positive = [
        "halflife_days",
        "max_acc_m",
        "max_loop_perimeter_km",
        "max_jump_speed_ms",
        "max_sustained_speed_ms",
        "sustained_window_s",
        "effort_cap_minutes",
        "closure_tol_m",
    ]
    non_negative = ["grace_days", "min_loop_area_km2"]
    bad = [f"{n}={getattr(cfg, n)!r} must be > 0" for n in positive if hasattr(cfg, n) and not getattr(cfg, n) > 0]
    bad += [
        f"{n}={getattr(cfg, n)!r} must be >= 0" for n in non_negative if hasattr(cfg, n) and not getattr(cfg, n) >= 0
    ]
    if hasattr(cfg, "h3_res") and not 0 <= cfg.h3_res <= 15:
        bad.append(f"h3_res={cfg.h3_res!r} must be 0..15")
    if bad:
        raise ValueError("invalid engine Config: " + "; ".join(bad))
