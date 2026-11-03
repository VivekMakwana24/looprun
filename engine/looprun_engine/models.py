"""Plain data types shared by the whole engine."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Fix:
    lat: float
    lng: float
    t: int  # epoch ms
    acc: float
    mock: bool = False


@dataclass(frozen=True)
class Config:
    """Every number is a tunable starting value."""

    h3_res: int = 10
    max_acc_m: float = 30.0
    closure_tol_m: float = 80.0
    min_loop_area_km2: float = 0.01  # about 0.7 cell
    max_loop_perimeter_km: float = 25.0
    max_jump_speed_ms: float = 12.5  # between two fixes -> hard flag "teleport"
    max_sustained_speed_ms: float = 7.0  # sustained over window_s -> hard flag "vehicle_speed"
    sustained_window_s: int = 60
    halflife_days: float = 14.0
    grace_days: float = 7.0
    max_freeze_days: int = 30
    effort_cap_minutes: float = 90.0


@dataclass(frozen=True)
class Loop:
    polygon: list[tuple[float, float]]  # (lat, lng) outer ring, closed
    area_km2: float
    cells: list[str]
    repaired: bool


@dataclass(frozen=True)
class Flag:
    code: str
    severity: str  # "hard" or "soft"
    detail: str


@dataclass(frozen=True)
class RunResult:
    distance_m: float
    moving_seconds: int
    loops: list[Loop]
    flags: list[Flag]
    cells: list[str]  # union of cells of all loops, unique, sorted

    @property
    def status(self) -> str:
        return "pending_review" if any(f.severity == "hard" for f in self.flags) else "accepted"


@dataclass
class CellPower:
    user_id: str
    power: float
    updated_at: int  # epoch ms


@dataclass(frozen=True)
class CellChange:
    cell: str
    old_owner: str | None
    new_owner: str | None
