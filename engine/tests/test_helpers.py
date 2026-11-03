"""cells_for_bbox, cell_centre, in_home_zone, gpx_to_fixes and the tools."""

import importlib.util
import subprocess
import sys
from pathlib import Path

import h3
import pytest

from looprun_engine import (
    Config,
    cell_centre,
    cells_for_bbox,
    gpx_to_fixes,
    in_home_zone,
)

TOOLS = Path(__file__).resolve().parents[1] / "tools"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def test_cell_centre_roundtrip():
    cell = h3.latlng_to_cell(50.0, 8.7, 10)
    lat, lng = cell_centre(cell)
    assert h3.latlng_to_cell(lat, lng, 10) == cell
    assert (lat, lng) == h3.cell_to_latlng(cell)


def test_cells_for_bbox_covers_every_point():
    box = (8.69, 49.99, 8.71, 50.01)
    cells = set(cells_for_bbox(*box))
    assert cells == set(cells_for_bbox(*box)) and list(cells_for_bbox(*box)) == sorted(cells)
    for lng in (8.69, 8.695, 8.70, 8.71):
        for lat in (49.99, 50.0, 50.01):
            assert h3.latlng_to_cell(lat, lng, 10) in cells
    area_km2 = 0.02 * 111.2 * 0.02 * 111.2 * 0.643
    assert len(cells) >= area_km2 / h3.average_hexagon_area(10, unit="km^2")


def test_cells_for_bbox_resolution_and_tiny_box():
    assert cells_for_bbox(8.7, 50.0, 8.70001, 50.00001)  # smaller than a cell still returns it
    coarse = cells_for_bbox(8.5, 49.9, 8.9, 50.1, res=7)
    assert all(h3.get_resolution(c) == 7 for c in coarse)


def test_cells_for_bbox_validation():
    with pytest.raises(ValueError):
        cells_for_bbox(9.0, 50.0, 8.0, 51.0)
    with pytest.raises(ValueError):
        cells_for_bbox(-10, 40, 30, 60)


def test_in_home_zone():
    cell = h3.latlng_to_cell(50.0, 8.7, 10)
    lat, lng = cell_centre(cell)
    assert in_home_zone(cell, [(lat, lng, 10.0)])
    assert in_home_zone(cell, [(lat + 0.001, lng, 200.0)])        # about 111 m away
    assert not in_home_zone(cell, [(lat + 0.01, lng, 200.0)])     # about 1.1 km away
    assert not in_home_zone(cell, [])
    assert in_home_zone(cell, [(0.0, 0.0, 5.0), (lat, lng, 5.0)])


def test_gpx_parse_fields():
    gpx = """<?xml version="1.0"?>
<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
<trkpt lat="50.1" lon="8.6"><time>2026-05-02T08:00:00.500Z</time>
  <extensions><acc>7.5</acc><mock>true</mock></extensions></trkpt>
<trkpt lat="50.2" lon="8.7"><time>2026-05-02T08:00:05Z</time><hdop>2</hdop></trkpt>
<trkpt lat="50.3" lon="8.8"><time>2026-05-02T10:00:05+02:00</time></trkpt>
</trkseg></trk></gpx>"""
    a, b, c = gpx_to_fixes(gpx)
    assert (a.lat, a.lng, a.acc, a.mock) == (50.1, 8.6, 7.5, True)
    assert a.t == 1777708800500
    assert b.acc == 10.0 and b.mock is False and b.t == 1777708805000
    assert c.acc == 5.0 and c.t == b.t


def test_gpx_rejects_missing_time_and_entities():
    with pytest.raises(ValueError):
        gpx_to_fixes('<gpx><trk><trkseg><trkpt lat="1" lon="2"/></trkseg></trk></gpx>')
    with pytest.raises(ValueError):
        gpx_to_fixes('<!DOCTYPE x [<!ENTITY a "b">]><gpx/>')


def test_gpx_empty():
    assert gpx_to_fixes("<gpx/>") == []


def test_replay_tool_output():
    out = subprocess.run(
        [sys.executable, str(TOOLS / "replay.py"), str(FIXTURES / "near_closed_60m.gpx")],
        capture_output=True, text=True, check=True,
    ).stdout
    for key in ("cleaned fixes:", "distance:", "loops:", "cells awarded:", "flags:", "status:"):
        assert key in out
    assert "repaired=True" in out and "near_closure_repaired" in out
    assert "status:         accepted" in out


def test_replay_tool_usage_error():
    p = subprocess.run([sys.executable, str(TOOLS / "replay.py")], capture_output=True, text=True)
    assert p.returncode == 2


def _load_simulate():
    spec = importlib.util.spec_from_file_location("simulate_tool", TOOLS / "simulate.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_simulation_steady_beats_single_run():
    sim = _load_simulate()
    cfg = Config()
    for name, events in sim.scenarios(cfg).items():
        result = sim.run_simulation(events, cfg)
        assert result["cells"], name
        assert set(result["final_owners"].values()) == {sim.STEADY}, name
        owners_over_time = [r["owners"] for r in result["rows"]]
        if name == "max_effort_single_run":
            # the single maximum-effort run owns the cells first and loses them later
            assert set(owners_over_time[1]) == {"F"} and set(owners_over_time[-1]) == {"S"}
        # the single run is the strongest single claim: nothing beats the cap
        cap_per_cell = cfg.effort_cap_minutes / len(result["cells"])
        assert max(r["fast_power"] for r in result["rows"]) <= cap_per_cell + 1e-9


def test_simulate_tool_runs():
    p = subprocess.run([sys.executable, str(TOOLS / "simulate.py")], capture_output=True, text=True)
    assert p.returncode == 0 and p.stdout.strip().endswith("PASS")
    assert "owner per cell" in p.stdout
