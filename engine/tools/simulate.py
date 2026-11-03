"""Steady runner vs one fast / maximum-effort run on the same cells.

Usage: python engine/tools/simulate.py
Prints, per scenario, the owner of every cell over time (S = steady, F = fast).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_fixtures  # noqa: E402

from looprun_engine import (  # noqa: E402
    CellPower,
    Config,
    apply_claim,
    effort_credit,
    faded_power,
    gpx_to_fixes,
    process_run,
)

DAY_MS = 86_400_000
STEADY, FAST = "steady", "fast"
LETTER = {STEADY: "S", FAST: "F", None: "."}


def _loop_run(cfg: Config):
    pts = make_fixtures.build("clean_square")
    return process_run(gpx_to_fixes(make_fixtures.gpx_text(pts)), cfg)


def scenarios(cfg: Config = Config()) -> dict[str, list[tuple[int, str, int]]]:
    """name -> list of (day, user, moving_seconds)."""
    loop_s = _loop_run(cfg).moving_seconds  # a normal-pace lap of the square
    steady_days = (3, 10, 17, 24)  # 4 runs over 3 weeks
    return {
        "max_effort_single_run": (
            [(1, FAST, int(cfg.effort_cap_minutes * 60))]  # best single run the rules allow
            + [(d, STEADY, 30 * 60) for d in steady_days]
        ),
        "fast_single_lap": (
            [(1, FAST, int(loop_s * 2 / 3))]  # same lap, a third faster -> less time
            + [(d, STEADY, loop_s) for d in steady_days]
        ),
    }


def _power(cell_powers: dict[str, CellPower], user: str, now: int, cfg: Config) -> float:
    return faded_power(cell_powers[user], now, cfg) if user in cell_powers else 0.0


def run_simulation(events: list[tuple[int, str, int]], cfg: Config = Config(),
                   horizon_days: int = 42, step_days: int = 3) -> dict:
    cells = _loop_run(cfg).cells
    n = len(cells)
    powers: dict[str, dict[str, CellPower]] = {c: {} for c in cells}
    owners: dict[str, str | None] = {c: None for c in cells}
    by_day: dict[int, list[tuple[str, int]]] = {}
    for day, user, moving in events:
        by_day.setdefault(day, []).append((user, moving))

    rows = []
    days = sorted(set(range(0, horizon_days + 1, step_days)) | set(by_day) | {horizon_days})
    for day in days:
        now = day * DAY_MS
        note = []
        for user, moving in by_day.get(day, []):
            credit = effort_credit(moving, n, cfg)
            note.append(f"{LETTER[user]} runs {moving / 60:.0f} min -> {credit:.2f}/cell")
            for c in cells:
                powers[c], change = apply_claim(c, powers[c], owners[c], user, credit, now, cfg)
                if change:
                    owners[c] = change.new_owner
        c0 = cells[0]
        rows.append({
            "day": day,
            "event": "; ".join(note),
            "owners": "".join(LETTER[owners[c]] for c in cells),
            "steady_power": _power(powers[c0], STEADY, now, cfg),
            "fast_power": _power(powers[c0], FAST, now, cfg),
        })
    return {"cells": cells, "rows": rows, "final_owners": dict(owners)}


def format_table(name: str, sim: dict) -> str:
    w = max(len("owner per cell"), len(sim["cells"]))
    lines = [f"== {name} ({len(sim['cells'])} cells)",
             f"{'day':>3}  {'owner per cell':<{w}}  {'S pow':>6}  {'F pow':>6}  event"]
    for r in sim["rows"]:
        lines.append(f"{r['day']:>3}  {r['owners']:<{w}}  "
                     f"{r['steady_power']:>6.2f}  {r['fast_power']:>6.2f}  {r['event']}")
    wins = sum(1 for o in sim["final_owners"].values() if o == STEADY)
    lines.append(f"result: steady runner owns {wins}/{len(sim['cells'])} cells at the end")
    return "\n".join(lines)


def main() -> int:
    cfg = Config()
    ok = True
    for name, events in scenarios(cfg).items():
        sim = run_simulation(events, cfg)
        print(format_table(name, sim))
        print()
        ok = ok and all(o == STEADY for o in sim["final_owners"].values())
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
