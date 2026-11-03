# Engine spec (`looprun_engine`, pure Python 3.11+, no I/O)

Dependencies allowed: `h3` (v4 API), `shapely` 2.x, `pyproj` (optional), stdlib. No Mongo, Redis, FastAPI.

## Public API (the server codes against exactly this)

```python
# looprun_engine/__init__.py exports:
@dataclass(frozen=True)
class Fix: lat: float; lng: float; t: int; acc: float; mock: bool = False   # t = epoch ms

@dataclass(frozen=True)
class Config:      # every number is a tunable starting value (see docs plan "Core rules")
    h3_res: int = 10
    max_acc_m: float = 30.0
    closure_tol_m: float = 80.0
    min_loop_area_km2: float = 0.01      # about 0.7 cell
    max_loop_perimeter_km: float = 25.0
    max_jump_speed_ms: float = 12.5      # between two fixes -> hard flag "teleport"
    max_sustained_speed_ms: float = 7.0  # sustained over window_s -> hard flag "vehicle_speed"
    sustained_window_s: int = 60
    halflife_days: float = 14.0
    grace_days: float = 7.0
    max_freeze_days: int = 30
    effort_cap_minutes: float = 90.0

@dataclass(frozen=True)
class Loop: polygon: list[tuple[float,float]]  # (lat,lng) outer ring, closed; area_km2: float; cells: list[str]; repaired: bool

@dataclass(frozen=True)
class Flag: code: str; severity: str; detail: str   # severity in {"hard","soft"}

@dataclass(frozen=True)
class RunResult:
    distance_m: float; moving_seconds: int; loops: list[Loop]; flags: list[Flag]
    cells: list[str]   # union of cells of all loops, unique, sorted
    @property
    def status(self) -> str: ...   # "pending_review" if any hard flag else "accepted"

def process_run(fixes: list[Fix], cfg: Config = Config()) -> RunResult
def effort_credit(moving_seconds: int, n_cells: int, cfg: Config = Config()) -> float
    # = min(moving_minutes, cfg.effort_cap_minutes) / n_cells, 0.0 if n_cells == 0

@dataclass
class CellPower: user_id: str; power: float; updated_at: int   # epoch ms

def faded_power(p: CellPower, now: int, cfg: Config = Config(), freeze_until: int | None = None) -> float
    # no fading for grace_days after updated_at; afterwards 0.5 ** (days_past_grace / halflife_days).
    # if freeze_until is in the future at `now`, power does not fade (treat fading time as stopped).

@dataclass(frozen=True)
class CellChange: cell: str; old_owner: str | None; new_owner: str | None

def apply_claim(cell: str, powers: dict[str, CellPower], current_owner: str | None, user_id: str,
                credit: float, now: int, cfg: Config = Config(),
                freezes: dict[str, int] | None = None) -> tuple[dict[str, CellPower], CellChange | None]
    # adds credit to user's faded power in that cell (stored power := faded + credit, updated_at := now),
    # then owner = user with highest faded power; a challenger takes the cell only if strictly greater
    # than the current owner's faded power (ties keep the owner). Returns new powers dict and the change if owner changed.

def cells_for_bbox(min_lng: float, min_lat: float, max_lng: float, max_lat: float, res: int = 10) -> list[str]
def cell_centre(cell: str) -> tuple[float, float]   # (lat, lng)
def in_home_zone(cell: str, zones: list[tuple[float, float, float]]) -> bool  # (lat,lng,radius_m)
def gpx_to_fixes(gpx_text: str) -> list[Fix]          # used by the replay tool and tests
```

## Behaviour (acceptance criteria)

1. **Clean fixes:** drop fixes with `acc > max_acc_m`; drop exact duplicate timestamps; require monotonic time (sort, drop out-of-order). Light smoothing allowed but must keep the first and last point within 5 m of raw.
2. **Loops:** a loop exists when the path self-intersects, or the last cleaned point is within `closure_tol_m` of an earlier point on the path (near-closure: join and mark `repaired=True`, plus a soft flag `near_closure_repaired`). Use shapely `unary_union`/`polygonize`. Reject loops with area < `min_loop_area_km2` or perimeter > `max_loop_perimeter_km` (add soft flag `loop_rejected_small` / `loop_rejected_large`).
3. **Cells:** `h3.h3shape_to_cells(h3.LatLngPoly(outer_latlng), cfg.h3_res)`; polygon coordinates are (lat, lng). Include holes if a loop contains another smaller ring only when it comes from a figure-eight (skip holes in v1).
4. **Flags (hard = no cells awarded, status pending_review):** any fix with `mock=True` -> `mock_location`; implied speed between two consecutive cleaned fixes > `max_jump_speed_ms` -> `teleport`; speed averaged over any `sustained_window_s` window > `max_sustained_speed_ms` -> `vehicle_speed`. **Soft:** loop area > 5 km2 or an edge longer than 2 km -> `implausible_loop`; fewer than 20 fixes -> `too_few_fixes`.
5. **Hard flags mean `RunResult.cells` is empty** (loops are still reported for review).
6. **moving_seconds:** time where speed between fixes is above 0.5 m/s; **distance_m:** sum of haversine between cleaned fixes.
7. Pure functions, deterministic, no global state, no clock (time comes from arguments).
8. Ownership rules exactly as in `apply_claim` and `faded_power` above; the Day-5 simulation must show that a steady runner (e.g. 4 runs over 3 weeks) beats a single faster run on the same cells.

## Test fixtures required (`engine/tests/fixtures/*.gpx`, generated by a script in `engine/tools/make_fixtures.py`, committed)

clean square loop (~400 m side, Frankfurt coordinates around 50.0, 8.7); figure eight; near-closed loop (end 60 m from start); near-closed loop (end 120 m from start, must NOT close); out-and-back (no loop); standing still with GPS jitter (no loop); car drive (vehicle_speed); teleport jump; mock-flagged run; tiny loop below min area.

## Tools

`engine/tools/replay.py <file.gpx>`: prints cleaned fix count, distance, loops, cells, flags, status as plain text.
`engine/tools/simulate.py`: runs the steady-vs-fast ownership simulation and prints a table of owner per cell over time (no plotting dependency).
