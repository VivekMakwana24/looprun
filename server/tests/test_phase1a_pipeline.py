"""Phase 1a area 1: battle_events and claimed-cell storage written by the claim pipeline (spec 0.4, 6)."""

from __future__ import annotations

import asyncio
import json

import pytest

from app import processing

from .conftest import db_run, hdr, login, run_loop, square_fixes
from .phase1a import K1, count, find, res_of
from .test_hardening import seed_run


def two_runs(c, a, b):
    first = run_loop(c, a, speed=3.0)
    second = run_loop(c, b, speed=1.5)  # more moving minutes: takes every cell
    return first, second


def test_a_takeover_writes_one_event_per_flipped_cell(make_app, clock):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    first, second = two_runs(c, a, b)
    n = second["cells_taken_from_others"]
    assert n == first["cells_claimed"] > 3
    events = find(c, "battle_events")
    assert len(events) == n
    run_b = find(c, "runs", {"user_id": b["_uid"]})[0]
    for e in events:
        assert e["_id"] == f"{run_b['_id']}:{e['cell']}"
        assert e["taker_id"] == b["_uid"] and e["victim_id"] == a["_uid"]
        assert e["run_id"] == run_b["_id"] and e["at"] == clock.now and e["k_ok"] is True  # K=1, taker counts
        assert e["expire_at"].year >= 2027  # 90 days ahead of the clock
    assert {e["cell"] for e in events} == set(run_b["claimed_cells"])


def test_no_event_for_first_claim_self_reclaim_or_a_failed_challenge(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)  # unowned cells: first claim
    assert count(c, "battle_events") == 0
    run_loop(c, a, speed=3.0)  # own cells again
    assert count(c, "battle_events") == 0
    st = run_loop(c, b, speed=5.0)  # too little power: nothing changes hands
    assert st["cells_claimed"] == 0
    assert count(c, "battle_events") == 0


def test_account_deletion_reassignment_creates_no_event(make_app):
    c = make_app(**K1)
    a, b, d = login(c, "alice"), login(c, "bob"), login(c, "dora")
    run_loop(c, a, speed=3.0)
    run_loop(c, b, speed=1.0)  # alice owns; bob holds the second-strongest power? no: bob took them (event)
    before = count(c, "battle_events")
    assert c.delete("/v1/me", headers=hdr(d)).status_code == 204  # unrelated user
    assert c.delete("/v1/me", headers=hdr(b)).status_code == 204  # cells pass back to alice: not a battle
    assert count(c, "battle_events", {"taker_id": {"$ne": b["_uid"]}}) == 0
    assert before > 0


def test_redelivered_run_creates_exactly_one_event_per_cell(make_app, monkeypatch):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    first = run_loop(c, a, speed=3.0)
    res = res_of(c)
    rid = seed_run(res, b["_uid"], square_fixes(speed=1.5))
    real_apply = processing._apply
    calls = {"n": 0}

    async def flaky(db, user_id, o):  # the worker dies after the 3rd cell, then the task is redelivered
        calls["n"] += 1
        if calls["n"] == 4:
            raise ConnectionError("worker killed")
        await real_apply(db, user_id, o)

    monkeypatch.setattr(processing, "_apply", flaky)
    with pytest.raises(ConnectionError):
        asyncio.run(processing.process_run_by_id(res, rid, final=False))
    assert count(c, "battle_events") == 3
    monkeypatch.setattr(processing, "_apply", real_apply)
    asyncio.run(processing.process_run_by_id(res, rid, final=True))
    run = find(c, "runs", {"_id": rid})[0]
    assert run["status"] == "accepted"
    assert count(c, "battle_events") == run["cells_taken_from_others"] == first["cells_claimed"]
    # applying the same outcome again (a second worker) is a no-op as well
    again = find(c, "battle_events")[0]
    asyncio.run(
        real_apply(res.db, b["_uid"], {"cell": again["cell"], "p": 1.0, "t": 1, "changed": False, "event": again})
    )
    assert count(c, "battle_events") == run["cells_taken_from_others"]


def test_k_ok_is_fixed_at_claim_time_from_the_neighbourhood(make_app):
    c = make_app(privacy_min_users=3)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    run_loop(c, b, speed=1.5)  # alice, bob: 2 users around the cells < 3
    assert {e["k_ok"] for e in find(c, "battle_events")} == {False}
    d, e_ = login(c, "dora"), login(c, "eve")
    run_loop(c, d, speed=5.0)  # too little power to own, but power rows exist: 3rd and 4th users nearby
    run_loop(c, e_, speed=5.0)
    f = login(c, "finn")
    run_loop(c, f, speed=0.8)  # takes from bob with alice, bob, dora, eve, finn around
    new = [x for x in find(c, "battle_events") if x["taker_id"] == f["_uid"]]
    assert new and {x["k_ok"] for x in new} == {True}
    assert {x["k_ok"] for x in find(c, "battle_events") if x["taker_id"] == b["_uid"]} == {False}  # history stays


def test_claimed_cells_are_stored_on_accepted_runs_only_and_never_in_the_run_status(make_app):
    c = make_app(**K1)
    a = login(c, "alice")
    st = run_loop(c, a)
    run = find(c, "runs", {"user_id": a["_uid"]})[0]
    assert len(run["claimed_cells"]) == st["cells_claimed"] > 0
    assert "claimed_cells" not in json.dumps(c.get(f"/v1/runs/{run['_id']}", headers=hdr(a)).json())
    held = run_loop(c, a, mock_every=7)  # pending_review
    assert held["status"] == "pending_review"
    held_doc = [r for r in find(c, "runs") if r["status"] == "pending_review"][0]
    assert "claimed_cells" not in held_doc
    short = [{"lat": 50.0, "lng": 8.7, "t": i * 1000, "acc": 5.0, "mock": False} for i in range(3)]
    rid = seed_run(res_of(c), a["_uid"], short)
    asyncio.run(processing.process_run_by_id(res_of(c), rid))
    doc = find(c, "runs", {"_id": rid})[0]
    assert doc["claimed_cells"] == [] and doc["status"] == "accepted"  # accepted without cells: empty list


def test_claim_plan_scrubbed_of_a_deleted_victim_writes_no_further_event(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    res = res_of(c)
    rid = seed_run(res, b["_uid"], square_fixes(speed=1.5))
    real_apply = processing._apply
    calls = {"n": 0}

    async def flaky(db, user_id, o):
        calls["n"] += 1
        if calls["n"] == 3:
            raise ConnectionError("worker killed")
        await real_apply(db, user_id, o)

    processing_apply = processing._apply
    processing._apply = flaky
    try:
        with pytest.raises(ConnectionError):
            asyncio.run(processing.process_run_by_id(res, rid, final=False))
    finally:
        processing._apply = processing_apply
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    asyncio.run(processing.process_run_by_id(res, rid, final=True))
    # the two cells applied before the crash keep their rows (account deletion anonymises them, area 9); the plan
    # of the rest was scrubbed of alice, so no further row appears
    assert len(find(c, "battle_events")) == 2
    assert a["_uid"] not in json.dumps(find(c, "run_claims"), default=str)
    assert db_run(c, lambda db: db.run_claims.count_documents({})) == 0
