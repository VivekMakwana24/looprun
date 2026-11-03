"""process_run and effort_credit."""

from __future__ import annotations

from .clean import clean_fixes
from .flags import cumulative_distance, speed_flags
from .loops import find_loops
from .models import Config, Fix, Flag, RunResult

MIN_FIXES = 20
IMPLAUSIBLE_AREA_KM2 = 5.0
IMPLAUSIBLE_EDGE_M = 2000.0
MOVING_SPEED_MS = 0.5


def process_run(fixes: list[Fix], cfg: Config = Config()) -> RunResult:
    flags: list[Flag] = []

    mock = sum(1 for f in fixes if f.mock)
    if mock:
        flags.append(Flag("mock_location", "hard", f"{mock} of {len(fixes)} fixes are mock"))

    cleaned = clean_fixes(fixes, cfg)
    if len(cleaned) < MIN_FIXES:
        flags.append(Flag("too_few_fixes", "soft",
                          f"{len(cleaned)} usable fixes, need {MIN_FIXES}"))

    cum = cumulative_distance(cleaned)
    distance_m = cum[-1]
    moving = 0.0
    for i in range(1, len(cleaned)):
        dt = (cleaned[i].t - cleaned[i - 1].t) / 1000
        if (cum[i] - cum[i - 1]) / dt > MOVING_SPEED_MS:
            moving += dt
    flags.extend(speed_flags(cleaned, cum, cfg))

    loops, loop_flags = find_loops(cleaned, cfg)
    flags.extend(loop_flags)
    if loops:
        longest = max((cum[i] - cum[i - 1] for i in range(1, len(cum))), default=0.0)
        big = max(lp.area_km2 for lp in loops)
        if big > IMPLAUSIBLE_AREA_KM2 or longest > IMPLAUSIBLE_EDGE_M:
            flags.append(Flag("implausible_loop", "soft",
                              f"largest loop {big:.2f} km2, longest edge {longest:.0f} m"))

    hard = any(f.severity == "hard" for f in flags)
    cells = [] if hard else sorted({c for lp in loops for c in lp.cells})
    return RunResult(
        distance_m=distance_m,
        moving_seconds=int(round(moving)),
        loops=loops,
        flags=flags,
        cells=cells,
    )


def effort_credit(moving_seconds: int, n_cells: int, cfg: Config = Config()) -> float:
    if n_cells <= 0:
        return 0.0
    minutes = max(0.0, moving_seconds / 60)
    return min(minutes, cfg.effort_cap_minutes) / n_cells
