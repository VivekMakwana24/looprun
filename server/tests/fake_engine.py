"""A small stand-in for looprun_engine (same public API as docs/ENGINE_SPEC.md), used until/unless the real
engine is installed. Deliberately simple: one loop when the path ends within 80 m of its start."""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import h3


@dataclass(frozen=True)
class Fix:
    lat: float
    lng: float
    t: int
    acc: float
    mock: bool = False


@dataclass(frozen=True)
class Config:
    halflife_days: float = 14.0
    grace_days: float = 7.0
    effort_cap_minutes: float = 90.0
    closure_tol_m: float = 80.0
    max_jump_speed_ms: float = 12.5
    min_loop_area_km2: float = 0.01


@dataclass(frozen=True)
class Loop:
    polygon: list
    area_km2: float
    cells: list
    repaired: bool = False


@dataclass(frozen=True)
class Flag:
    code: str
    severity: str
    detail: str


@dataclass(frozen=True)
class RunResult:
    distance_m: float
    moving_seconds: int
    loops: list = field(default_factory=list)
    flags: list = field(default_factory=list)
    cells: list = field(default_factory=list)

    @property
    def status(self) -> str:
        return "pending_review" if any(f.severity == "hard" for f in self.flags) else "accepted"


def _hav(a, b) -> float:
    p1, p2 = math.radians(a.lat), math.radians(b.lat)
    dphi, dl = p2 - p1, math.radians(b.lng - a.lng)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * 6371000.0 * math.asin(math.sqrt(h))


def process_run(fixes, cfg: Config = Config()) -> RunResult:
    fx = sorted(fixes, key=lambda f: f.t)
    dist, moving, flags = 0.0, 0, []
    for a, b in zip(fx, fx[1:], strict=False):
        d, dt = _hav(a, b), (b.t - a.t) / 1000
        dist += d
        if dt > 0 and d / dt > 0.5:
            moving += round(dt)
        if dt > 0 and d / dt > cfg.max_jump_speed_ms:
            flags.append(Flag("teleport", "hard", "jump"))
            break
    if any(f.mock for f in fx):
        flags.append(Flag("mock_location", "hard", "mock"))
    if len(fx) < 20:
        flags.append(Flag("too_few_fixes", "soft", str(len(fx))))
    loops, cells = [], []
    if len(fx) >= 20 and _hav(fx[0], fx[-1]) <= cfg.closure_tol_m:
        ring = [(f.lat, f.lng) for f in fx] + [(fx[0].lat, fx[0].lng)]
        cs = sorted(h3.h3shape_to_cells(h3.LatLngPoly(ring), 10))
        if cs:
            loops.append(Loop(ring, len(cs) * 0.015, cs))
            cells = cs
    if any(f.severity == "hard" for f in flags):
        cells = []
    return RunResult(dist, moving, loops, flags, cells)


def effort_credit(moving_seconds: int, n_cells: int, cfg: Config = Config()) -> float:
    if n_cells == 0:
        return 0.0
    return min(moving_seconds / 60, cfg.effort_cap_minutes) / n_cells


@dataclass
class CellPower:
    user_id: str
    power: float
    updated_at: int


def faded_power(p: CellPower, now: int, cfg: Config = Config(), freeze_until: int | None = None) -> float:
    if freeze_until is not None and freeze_until > now:
        return p.power
    days = (now - p.updated_at) / 86_400_000
    over = max(0.0, days - cfg.grace_days)
    return p.power * 0.5 ** (over / cfg.halflife_days)


@dataclass(frozen=True)
class CellChange:
    cell: str
    old_owner: str | None
    new_owner: str | None


def apply_claim(cell, powers, current_owner, user_id, credit, now, cfg: Config = Config(), freezes=None):
    freezes = freezes or {}
    new = dict(powers)
    mine = new.get(user_id)
    base = faded_power(mine, now, cfg, freezes.get(user_id)) if mine else 0.0
    new[user_id] = CellPower(user_id, base + credit, now)
    best_u, best_p = current_owner, -1.0
    if current_owner is not None and current_owner in new:
        best_p = faded_power(new[current_owner], now, cfg, freezes.get(current_owner)) if current_owner != user_id else new[user_id].power
    for u, cp in new.items():
        p = cp.power if u == user_id else faded_power(cp, now, cfg, freezes.get(u))
        if p > best_p:
            best_u, best_p = u, p
    change = CellChange(cell, current_owner, best_u) if best_u != current_owner else None
    return new, change


def cell_centre(cell: str):
    return h3.cell_to_latlng(cell)


def in_home_zone(cell: str, zones) -> bool:
    lat, lng = h3.cell_to_latlng(cell)
    c = Fix(lat, lng, 0, 0)
    return any(_hav(c, Fix(z[0], z[1], 0, 0)) <= z[2] for z in zones)
