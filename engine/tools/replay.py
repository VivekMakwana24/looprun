"""Replay a GPX file through the engine and print a plain-text report.

Usage: python engine/tools/replay.py <file.gpx>
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from looprun_engine import Config, gpx_to_fixes, process_run  # noqa: E402
from looprun_engine.clean import clean_fixes  # noqa: E402


def report(gpx_text: str, cfg: Config = Config()) -> str:
    fixes = gpx_to_fixes(gpx_text)
    cleaned = clean_fixes(fixes, cfg)
    res = process_run(fixes, cfg)
    out = [
        f"raw fixes:      {len(fixes)}",
        f"cleaned fixes:  {len(cleaned)}",
        f"distance:       {res.distance_m:.1f} m",
        f"moving time:    {res.moving_seconds} s",
        f"loops:          {len(res.loops)}",
    ]
    for i, lp in enumerate(res.loops, 1):
        out.append(f"  loop {i}: area {lp.area_km2:.4f} km2, {len(lp.cells)} cells, "
                   f"repaired={lp.repaired}")
    out.append(f"cells awarded:  {len(res.cells)}")
    for c in res.cells:
        out.append(f"  {c}")
    out.append(f"flags:          {len(res.flags)}")
    for f in res.flags:
        out.append(f"  [{f.severity}] {f.code}: {f.detail}")
    out.append(f"status:         {res.status}")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: replay.py <file.gpx>", file=sys.stderr)
        return 2
    print(report(Path(argv[1]).read_text(encoding="utf-8")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
