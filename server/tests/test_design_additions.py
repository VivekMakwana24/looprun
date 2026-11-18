"""D10: additive fields for the app redesign (cell boundary and strength, leaderboard `me`, GET /me)."""

from __future__ import annotations

import h3
import pytest

from app import engine_adapter

from .conftest import cells_of, db_run, hdr, login, run_loop, square_fixes, upload


# ------------------------------------------------------------------ boundary
def test_cells_carry_the_hexagon_boundary(client):
    a = login(client, "alice")
    run_loop(client, a)
    cells = cells_of(client, a)
    assert cells
    for c in cells:
        assert c["boundary"] == [list(p) for p in h3.cell_to_boundary(c["id"])]
        assert len(c["boundary"]) == 6 and all(len(p) == 2 for p in c["boundary"])
        # old fields are still there
        assert {"id", "lat", "lng", "owner", "mine", "hidden"} <= set(c)


def test_engine_adapter_boundary_matches_the_centre(client):
    cell = h3.latlng_to_cell(50.0, 8.7, 10)
    ring = engine_adapter.cell_boundary(cell)
    lat, lng = engine_adapter.cell_centre(cell)
    assert sum(p[0] for p in ring) / 6 == pytest.approx(lat, abs=1e-5)
    assert sum(p[1] for p in ring) / 6 == pytest.approx(lng, abs=1e-5)


# ------------------------------------------------------------------ strength
def _strengths(client, h):
    return [c.get("strength") for c in cells_of(client, h) if c["mine"]]


def test_strength_is_one_in_grace_and_fades_afterwards(client, clock):
    a = login(client, "alice")
    run_loop(client, a)
    assert set(_strengths(client, a)) == {1.0}
    clock.advance(days=7)  # the grace period ends now
    assert set(_strengths(client, a)) == {1.0}
    clock.advance(days=14)  # one half-life later
    assert set(_strengths(client, a)) == {0.5}
    clock.advance(days=14)
    assert set(_strengths(client, a)) == {0.25}


def test_running_the_loop_again_restores_strength(client, clock):
    a = login(client, "alice")
    run_loop(client, a)
    clock.advance(days=30)
    assert all(s < 0.5 for s in _strengths(client, a))
    run_loop(client, a, t0=clock.now)
    assert set(_strengths(client, a)) == {1.0}


def test_strength_is_never_sent_for_other_players(client, clock):
    hs = [login(client, n) for n in ("alice", "bob", "carol")]
    for h in hs:  # three users nearby, so names are public (K-anonymity)
        run_loop(client, h)
    clock.advance(days=20)
    owner_id = db_run(client, lambda db: db.cells.distinct("owner_id"))[0]
    owner = next(h for h in hs if h["_uid"] == owner_id)
    stranger = next(h for h in hs if h["_uid"] != owner_id)
    mine = cells_of(client, owner)
    assert mine and all(c["mine"] and 0 < c["strength"] < 1 for c in mine)
    seen = cells_of(client, stranger)
    assert seen and all(not c["mine"] for c in seen)
    assert all("strength" not in c for c in seen)
    assert any(c["owner"] is not None for c in seen)


def test_strength_respects_a_running_freeze(client, clock):
    a = login(client, "alice")
    run_loop(client, a)
    clock.advance(days=21)
    assert set(_strengths(client, a)) == {0.5}
    assert client.post("/v1/me/freeze", json={"days": 10}, headers=hdr(a)).status_code == 200
    clock.advance(days=9)
    # frozen: nothing fades, and the hold stays as weak as it was when the rest days began (it is not
    # reported as full just because the stored power was rebased at the freeze start).
    assert set(_strengths(client, a)) == {0.5}
    clock.advance(days=2)  # the freeze ran out a day ago: fading goes on from 0.5
    after = _strengths(client, a)
    assert all(0.45 < s < 0.5 for s in after)
    run_loop(client, a, t0=clock.now)  # running the loop again restores the hold
    assert set(_strengths(client, a)) == {1.0}


def test_strength_forgives_an_expired_freeze_that_is_not_settled_yet(client, clock):
    a = login(client, "alice")
    run_loop(client, a)
    assert client.post("/v1/me/freeze", json={"days": 10}, headers=hdr(a)).status_code == 200
    clock.advance(days=15)  # the freeze ran out 5 days ago; nothing has settled it (settling is lazy)
    u = db_run(client, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert u["freeze_until"] is not None and u["freeze_until"] < clock.now
    # 15 days since the run, 10 of them frozen: 5 unfrozen days, still inside the 7-day grace period
    assert set(_strengths(client, a)) == {1.0}
    clock.advance(days=16)  # 21 unfrozen days: grace + one half-life
    assert set(_strengths(client, a)) == {0.5}
    # reading never writes: the freeze is still unsettled
    u = db_run(client, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert u["freeze_until"] is not None


def test_websocket_frame_to_the_new_owner_has_boundary_and_strength(client):
    a = login(client, "a")
    tok = a["Authorization"].split()[1]
    with client.websocket_connect("/v1/live?bbox=8.6,49.9,8.8,50.1") as ws:
        ws.send_json({"type": "auth", "token": tok})
        upload(client, a, square_fixes())
        msg = ws.receive_json()
    assert msg["mine"] is True and msg["strength"] == 1.0
    assert msg["boundary"] == engine_adapter.cell_boundary(msg["cell"])


# ------------------------------------------------------------------ leaderboard me
def test_leaderboard_me_gives_the_callers_rank_and_cells(client):
    a, b, c = login(client, "alice"), login(client, "bob"), login(client, "carol")
    run_loop(client, a)
    run_loop(client, b, lat=50.02, side_m=250.0)
    board = client.get("/v1/leaderboard/weekly", headers=hdr(b)).json()
    mine = next(e for e in board["entries"] if e["user"]["id"] == b["_uid"])
    assert board["me"] == {"rank": mine["rank"], "cells": mine["cells"]}
    assert board["me"]["cells"] == len([x for x in cells_of(client, b) if x["mine"]])
    # somebody without cells is not ranked
    assert client.get("/v1/leaderboard/weekly", headers=hdr(c)).json()["me"] == {"rank": None, "cells": 0}


def test_leaderboard_me_is_given_even_below_the_listed_entries(make_app):
    c = make_app(leaderboard_size=1, privacy_min_users=1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    run_loop(c, b, lat=50.02, side_m=250.0)
    board = c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()
    assert len(board["entries"]) == 1 and board["entries"][0]["user"]["id"] == a["_uid"]
    assert board["me"]["rank"] == 2 and board["me"]["cells"] > 0


# ------------------------------------------------------------------ GET /me
def test_get_me_returns_name_zones_and_freeze_quota(client, clock):
    a = login(client, "alice")
    me = client.get("/v1/me", headers=hdr(a)).json()
    assert me == {
        "user": {"id": a["_uid"], "name": "alice"},
        "home_zones": [],
        "freeze": {"freeze_until": None, "used_days": 0, "quota_days": 30, "window_days": 90},
        "name_hidden": False,  # Phase 1a, additive
    }
    zone = {"lat": 50.0, "lng": 8.7, "radius_m": 300.0}
    assert client.put("/v1/me/home-zones", json={"zones": [zone]}, headers=hdr(a)).status_code == 204
    started = client.post("/v1/me/freeze", json={"days": 12}, headers=hdr(a)).json()
    assert started["freeze_until"] == clock.now + 12 * 86_400_000 and started["used_days"] == 0
    clock.advance(days=4, seconds=1)
    me = client.get("/v1/me", headers=hdr(a)).json()
    assert me["home_zones"] == [zone]
    assert me["freeze"]["freeze_until"] == started["freeze_until"]
    assert me["freeze"]["used_days"] == 5  # 4 days and a bit, rounded up
    clock.advance(days=20)  # the freeze ran out after 12 days
    me = client.get("/v1/me", headers=hdr(a)).json()
    assert me["freeze"] == {"freeze_until": None, "used_days": 12, "quota_days": 30, "window_days": 90}
    clock.advance(days=80)  # day 104: the freeze (days 0..12) has left the 90-day window
    assert client.get("/v1/me", headers=hdr(a)).json()["freeze"]["used_days"] == 0


def test_get_me_needs_a_token_and_refuses_a_deleting_account(client):
    assert client.get("/v1/me").status_code == 401
    a = login(client, "alice")
    db_run(client, lambda db: db.users.update_one({"_id": a["_uid"]}, {"$set": {"deleting": True}}))
    assert client.get("/v1/me", headers=hdr(a)).status_code == 403
