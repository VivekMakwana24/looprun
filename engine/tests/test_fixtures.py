"""One test group per GPX fixture, plus a check that the committed files match the generator."""

from pathlib import Path

import h3
import make_fixtures
import pytest
from shapely.geometry import Point, Polygon

from looprun_engine import Config

CELL_KM2 = h3.average_hexagon_area(Config().h3_res, unit="km^2")


def codes(result):
    return {f.code for f in result.flags}


def test_committed_fixtures_match_generator(tmp_path):
    make_fixtures.write_all(tmp_path)
    committed_dir = Path(__file__).parent / "fixtures"
    assert sorted(p.name for p in committed_dir.glob("*.gpx")) == sorted(
        p.name for p in tmp_path.glob("*.gpx")
    )
    for p in tmp_path.glob("*.gpx"):
        assert (committed_dir / p.name).read_text() == p.read_text()


def test_clean_square_loop(run):
    r = run("clean_square")
    assert r.status == "accepted" and r.flags == []
    assert len(r.loops) == 1
    loop = r.loops[0]
    assert loop.repaired is False
    assert loop.polygon[0] == loop.polygon[-1]
    assert loop.area_km2 == pytest.approx(0.16, rel=0.03)
    expected = loop.area_km2 / CELL_KM2  # about 10.6
    assert 0.7 * expected <= len(r.cells) <= 1.3 * expected
    assert 8 <= len(r.cells) <= 14
    assert r.cells == sorted(set(r.cells)) == sorted(loop.cells)
    assert 1580 < r.distance_m < 1700  # 1600 m plus noise
    assert 500 <= r.moving_seconds <= 540


def test_clean_square_cell_centres_inside_polygon(run):
    loop = run("clean_square").loops[0]
    poly = Polygon([(lng, lat) for lat, lng in loop.polygon])
    for c in loop.cells:
        lat, lng = h3.cell_to_latlng(c)
        assert poly.contains(Point(lng, lat))


def test_figure_eight_two_loops(run):
    r = run("figure_eight")
    assert len(r.loops) == 2
    assert all(lp.area_km2 > Config().min_loop_area_km2 for lp in r.loops)
    assert r.cells and r.status == "accepted"
    assert set(r.cells) == set(r.loops[0].cells) | set(r.loops[1].cells)


def test_near_closed_60m_is_repaired(run):
    r = run("near_closed_60m")
    assert len(r.loops) == 1 and r.loops[0].repaired is True
    assert "near_closure_repaired" in codes(r)
    assert next(f for f in r.flags if f.code == "near_closure_repaired").severity == "soft"
    assert r.status == "accepted" and r.cells


def test_near_closed_120m_does_not_close(run):
    r = run("near_closed_120m")
    assert r.loops == [] and r.cells == []
    assert "near_closure_repaired" not in codes(r)


def test_out_and_back_has_no_loop(run):
    r = run("out_and_back")
    assert r.loops == [] and r.cells == [] and r.status == "accepted"


def test_jitter_has_no_loop(run):
    r = run("jitter")
    assert r.loops == [] and r.cells == [] and r.status == "accepted"


def test_car_drive_flagged_vehicle_speed(run):
    r = run("car_drive")
    assert "vehicle_speed" in codes(r) and "teleport" not in codes(r)
    assert r.status == "pending_review"
    assert r.cells == []
    assert len(r.loops) == 1  # still reported for review
    assert r.loops[0].cells  # loop keeps its cells, only RunResult.cells is emptied


def test_teleport_flagged(run):
    r = run("teleport")
    assert "teleport" in codes(r)
    assert next(f for f in r.flags if f.code == "teleport").severity == "hard"
    assert r.status == "pending_review" and r.cells == []


def test_mock_flagged_and_cells_empty(run):
    r = run("mock")
    assert "mock_location" in codes(r)
    assert r.status == "pending_review"
    assert r.cells == []
    assert r.loops  # reported for review


def test_tiny_loop_rejected(run):
    r = run("tiny_loop")
    assert r.loops == [] and r.cells == []
    assert "loop_rejected_small" in codes(r)
    assert r.status == "accepted"  # soft flag only


def test_gps_dropout_loop_still_found(run, load):
    r = run("gps_dropout")
    assert len(r.loops) == 1 and r.cells and r.status == "accepted"
    assert not codes(r) & {"teleport", "vehicle_speed"}
    fx = load("gps_dropout")
    gap = max(b.t - a.t for a, b in zip(fx, fx[1:], strict=False))
    assert 40_000 <= gap <= 50_000  # the outage is really in the file
    # straight line across the gap is counted: distance stays close to the full 1600 m square
    assert 1550 < r.distance_m < 1700


def test_tunnel_loop_found_no_hard_flags(run, load):
    r = run("tunnel")
    assert len(r.loops) == 1 and r.cells and r.status == "accepted"
    assert not [f for f in r.flags if f.severity == "hard"]
    fx = load("tunnel")
    assert max(b.t - a.t for a, b in zip(fx, fx[1:], strict=False)) >= 90_000
    # chord across a corner is shorter than the route, but the loop area is nearly intact
    assert r.loops[0].area_km2 > 0.14


def test_bowtie_two_lobes(run):
    r = run("bowtie")
    assert len(r.loops) == 2 and r.status == "accepted"
    assert not [f for f in r.flags if f.severity == "hard"]
    for lp in r.loops:
        assert lp.area_km2 == pytest.approx(0.04, rel=0.1) and lp.cells
    assert set(r.cells) == set(r.loops[0].cells) | set(r.loops[1].cells)
