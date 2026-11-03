"""Cleaning, metrics, flags and purity, using small synthetic runs."""

import random
from dataclasses import replace

import make_fixtures
import pytest

from looprun_engine import Config, Fix, gpx_to_fixes, process_run
from looprun_engine.clean import clean_fixes

LAT0, LNG0, T0 = 50.0, 8.7, 1_780_000_000_000
M_PER_DEG_LAT = 111_195.0  # R * pi / 180 with R = 6371008.8


def line(n, speed, dt=5, acc=5.0, **kw):
    """n fixes heading north at `speed` m/s, one every dt seconds."""
    return [
        Fix(LAT0 + speed * dt * k / M_PER_DEG_LAT, LNG0, T0 + k * dt * 1000, acc, **kw)
        for k in range(n)
    ]


def codes(r):
    return {f.code for f in r.flags}


# ---- 1. cleaning ----------------------------------------------------------

def test_cleaning_drops_bad_accuracy():
    fx = line(5, 2)
    fx[2] = replace(fx[2], acc=30.1)
    fx[3] = replace(fx[3], acc=30.0)  # boundary is kept
    out = clean_fixes(fx, Config())
    assert [f.t for f in out] == [fx[0].t, fx[1].t, fx[3].t, fx[4].t]


def test_cleaning_drops_duplicate_timestamps_keeps_first():
    fx = line(4, 2)
    dup = replace(fx[1], lat=fx[1].lat + 0.001)
    out = clean_fixes([fx[0], fx[1], dup, fx[2], fx[3]], Config())
    assert len(out) == 4 and out[1] == fx[1]


def test_cleaning_sorts_out_of_order():
    fx = line(5, 2)
    out = clean_fixes([fx[0], fx[3], fx[1], fx[2], fx[4]], Config())
    assert out == fx


def test_cleaning_keeps_endpoints_exactly():
    fx = line(10, 2)
    out = clean_fixes(fx, Config())
    assert out[0] == fx[0] and out[-1] == fx[-1]


def test_cleaning_drops_invalid_coordinates():
    fx = line(3, 2) + [Fix(float("nan"), 8.7, T0 + 99_000, 5), Fix(95.0, 8.7, T0 + 100_000, 5)]
    assert len(clean_fixes(fx, Config())) == 3


# ---- 6. metrics -----------------------------------------------------------

def test_distance_and_moving_seconds():
    r = process_run(line(30, 2.0))  # 29 hops of 10 m
    assert r.distance_m == pytest.approx(290, rel=0.01)
    assert r.moving_seconds == 145


def test_standing_still_has_no_moving_time():
    fx = [Fix(LAT0, LNG0, T0 + k * 5000, 5.0) for k in range(30)]
    r = process_run(fx)
    assert r.distance_m == 0 and r.moving_seconds == 0


def test_slow_hops_below_threshold_not_moving():
    r = process_run(line(30, 0.4))
    assert r.moving_seconds == 0 and r.distance_m > 0


def test_empty_input():
    r = process_run([])
    assert r.distance_m == 0 and r.moving_seconds == 0 and r.loops == [] and r.cells == []
    assert "too_few_fixes" in codes(r) and r.status == "accepted"


# ---- 4. flags -------------------------------------------------------------

def test_too_few_fixes_is_soft():
    r = process_run(line(19, 2))
    f = next(f for f in r.flags if f.code == "too_few_fixes")
    assert f.severity == "soft" and r.status == "accepted"
    assert "too_few_fixes" not in codes(process_run(line(20, 2)))


def test_mock_flag_uses_raw_fixes_even_if_dropped_by_cleaning():
    fx = line(30, 2)
    fx[4] = replace(fx[4], mock=True, acc=99.0)  # would be dropped by accuracy filter
    r = process_run(fx)
    assert "mock_location" in codes(r) and r.status == "pending_review"


@pytest.mark.parametrize("speed,expected", [(6.9, False), (7.1, True)])
def test_vehicle_speed_threshold(speed, expected):
    assert ("vehicle_speed" in codes(process_run(line(40, speed)))) is expected


def test_short_burst_does_not_trigger_vehicle_speed():
    # 8 m/s for 30 s inside an otherwise 2 m/s run: any 60 s window averages well below 7
    fx, lat = [], LAT0
    for k in range(60):
        v = 8.0 if 20 <= k < 26 else 2.0
        fx.append(Fix(lat, LNG0, T0 + k * 5000, 5.0))
        lat += v * 5 / M_PER_DEG_LAT
    assert "vehicle_speed" not in codes(process_run(fx))


@pytest.mark.parametrize("speed,expected", [(12.0, False), (13.0, True)])
def test_teleport_threshold(speed, expected):
    fx = line(30, 0.5)
    extra = (speed * 5 - 0.5 * 5) / M_PER_DEG_LAT  # make hop 15 -> 16 run at `speed`
    fx = fx[:16] + [replace(f, lat=f.lat + extra) for f in fx[16:]]
    assert ("teleport" in codes(process_run(fx))) is expected


def test_implausible_loop_by_area_is_soft_and_still_awards_cells():
    rng = random.Random(1)
    pts = make_fixtures.walk(make_fixtures.square(2500), 3.0, 5, rng)
    r = process_run(gpx_to_fixes(make_fixtures.gpx_text(pts)))
    assert len(r.loops) == 1 and r.loops[0].area_km2 > 5
    f = next(f for f in r.flags if f.code == "implausible_loop")
    assert f.severity == "soft" and r.status == "accepted" and r.cells


def test_loop_rejected_large_by_perimeter():
    rng = random.Random(2)
    pts = make_fixtures.walk(make_fixtures.square(7000), 3.0, 5, rng, noise_m=1.0)
    r = process_run(gpx_to_fixes(make_fixtures.gpx_text(pts)))
    assert r.loops == [] and "loop_rejected_large" in codes(r)


def test_config_changes_behaviour():
    pts = make_fixtures.build("near_closed_60m")
    fixes = gpx_to_fixes(make_fixtures.gpx_text(pts))
    assert process_run(fixes).loops
    assert process_run(fixes, Config(closure_tol_m=50.0)).loops == []
    big_min = Config(min_loop_area_km2=0.5)
    r = process_run(fixes, big_min)
    assert r.loops == [] and "loop_rejected_small" in codes(r)


# ---- 7. purity ------------------------------------------------------------

def test_deterministic_and_does_not_mutate_input():
    fixes = gpx_to_fixes(make_fixtures.gpx_text(make_fixtures.build("figure_eight")))
    snapshot = list(fixes)
    a, b = process_run(fixes), process_run(fixes)
    assert a == b and fixes == snapshot


def test_status_property():
    assert process_run(line(30, 2)).status == "accepted"
    assert process_run(line(30, 10)).status == "pending_review"


def test_gap_with_impossible_speed_is_teleport():
    fx = line(30, 2)
    gap_deg = 5000 / M_PER_DEG_LAT  # 5 km in the 30 s the gap lasts
    fx = fx[:15] + [replace(f, lat=f.lat + gap_deg, t=f.t + 25_000) for f in fx[15:]]
    r = process_run(fx)
    tp = next(f for f in r.flags if f.code == "teleport")
    assert tp.severity == "hard" and r.status == "pending_review" and r.cells == []


@pytest.mark.parametrize("speed,expected", [(6.0, False), (8.0, True)])
def test_short_run_under_window_checked_for_vehicle_speed(speed, expected):
    fx = line(10, speed, dt=3)  # 27 s, shorter than the 60 s window
    assert fx[-1].t - fx[0].t < 60_000
    assert ("vehicle_speed" in codes(process_run(fx))) is expected
