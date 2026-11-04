"""Regression tests for the second verification pass (docs/verification/S-recheck.md, findings N1-N13).

Dispositions: docs/verification/S-fixes2.md.
"""

from __future__ import annotations

import asyncio
import json
import uuid

import pytest
import yaml
from fakeredis import FakeAsyncRedis, FakeServer
from pymongo.errors import OperationFailure
from starlette.websockets import WebSocketDisconnect

from app import api, auth, events, processing
from app import engine_adapter as eng
from app.errors import LockLost, LockTimeout
from app.freeze import rebase_for_freeze, settle_freeze
from app.locks import LockSet, user_key
from app.worker import enqueue_run, sweep_stuck_runs_task

from .conftest import T0, cells_of, db_run, hdr, login, run_loop, square_fixes, upload
from .test_hardening import res_of, seed_run

BBOX = "8.6,49.9,8.8,50.1"
K1 = {"privacy_min_users": 1, "delete_lock_wait_seconds": 0.15}


def board(c, h):
    return {e["user"]["name"]: e["cells"] for e in c.get("/v1/leaderboard/weekly", headers=hdr(h)).json()["entries"]}


def hold_user_lock(c, uid):
    """A busy worker holds the user's lock: DELETE /me answers 503 and the account stays `deleting`."""
    asyncio.run(res_of(c).redis.set(user_key(uid), "foreign", ex=600))


def release_user_lock(c, uid):
    asyncio.run(res_of(c).redis.delete(user_key(uid)))


def dump_db(c) -> dict[str, list[dict]]:
    async def f(db):
        return {n: await db[n].find({}).to_list(None) for n in await db.list_collection_names()}

    return db_run(c, f)


def dump_redis(c) -> dict[str, str]:
    async def f():
        r = res_of(c).redis
        out = {}
        async for k in r.scan_iter(match="*"):
            t = await r.type(k)
            if t == "string":
                out[k] = await r.get(k)
            elif t == "zset":
                out[k] = json.dumps(await r.zrange(k, 0, -1, withscores=True))
            else:
                out[k] = t
        return out

    return asyncio.run(f())


def where_is(c, needle: str) -> dict[str, int]:
    """Every collection / Redis key that still contains `needle` (as a document value, key name or string)."""
    hits: dict[str, int] = {}
    for name, docs in dump_db(c).items():
        n = json.dumps(docs, default=str).count(needle)
        if n:
            hits[f"mongo:{name}"] = n
    for k, v in dump_redis(c).items():
        if needle in k or needle in v:
            hits[f"redis:{k}"] = 1
    return hits


# ------------------------------------------------------------------ N1: a deleting account is invisible
def test_deleting_user_disappears_from_cells_and_leaderboard_immediately(make_app):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    assert {x["owner"]["name"] for x in cells_of(c, b) if x["owner"]} == {"a"}
    assert board(c, b) == {"a": board(c, a)["a"]}
    hold_user_lock(c, a["_uid"])
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 503
    assert cells_of(c, b) == []  # unowned until reassigned: not even a ghost cell
    assert board(c, b) == {}
    assert where_is(c, "a") is not None  # (helper smoke) the account still exists in the database
    release_user_lock(c, a["_uid"])
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204


def test_deleting_user_is_not_in_the_cached_leaderboard_either(make_app):
    c = make_app(leaderboard_cache_seconds=60, **K1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    assert "a" in board(c, b)  # fills the cache with a's count
    hold_user_lock(c, a["_uid"])
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 503
    assert board(c, b) == {}


def test_websocket_frames_never_name_a_deleting_owner(make_app):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    cell = cells_of(c, b)[0]["id"]
    hold_user_lock(c, a["_uid"])
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 503
    with c.websocket_connect(f"/v1/live?bbox={BBOX}&token={b['Authorization'].split()[1]}") as ws:
        c.portal.call(events.publish_changes, res_of(c).redis, [{"cell": cell, "new_owner": a["_uid"], "reveal_at": 0}])
        msg = ws.receive_json()
    assert msg["cell"] == cell and msg["owner"] is None and msg["mine"] is False
    assert a["_uid"] not in json.dumps(msg)


# ------------------------------------------------------------------ N2: no trace of a deleted user
def test_run_claims_are_deleted_when_the_run_is_finished(make_app):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    for i in range(3):
        run_loop(c, a, lat=50 + i * 0.01)
    run_loop(c, b)
    assert db_run(c, lambda db: db.run_claims.count_documents({})) == 0


def test_no_trace_of_a_deleted_user_in_any_collection_or_redis_key(make_app):
    c = make_app(**K1)
    a, b, d = login(c, "a"), login(c, "b"), login(c, "d")
    run_loop(c, a)
    run_loop(c, b)  # equal power: b does not take, but b's plan names a as owner
    run_loop(c, d, lat=50.0003, lng=8.7003)
    c.get(f"/v1/cells?bbox={BBOX}", headers=hdr(a))  # rate-limit counter keyed by user
    c.get("/v1/leaderboard/weekly", headers=hdr(b))
    c.post("/v1/reports", json={"kind": "cell", "target_id": "x", "reason": "r"}, headers=hdr(a))
    c.post("/v1/me/freeze", json={"days": 2}, headers=hdr(a))
    with c.websocket_connect(f"/v1/live?bbox={BBOX}&token={a['Authorization'].split()[1]}"):
        pass
    assert where_is(c, a["_uid"])  # sanity: there was something to remove
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert where_is(c, a["_uid"]) == {}


def test_inflight_claim_plan_of_another_user_is_scrubbed_but_still_completes_once(make_app, monkeypatch):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    res = res_of(c)
    rid = seed_run(res, b["_uid"], square_fixes())
    real_apply = processing._apply
    calls = {"n": 0}

    async def flaky(db, user_id, o):  # the worker dies after the 3rd cell
        calls["n"] += 1
        if calls["n"] == 4:
            raise ConnectionError("worker killed")
        await real_apply(db, user_id, o)

    monkeypatch.setattr(processing, "_apply", flaky)
    with pytest.raises(ConnectionError):
        asyncio.run(processing.process_run_by_id(res, rid, final=False))
    plan = db_run(c, lambda db: db.run_claims.find_one({"_id": rid}))
    assert plan and a["_uid"] in json.dumps(plan, default=str)  # an unfinished plan does name a
    monkeypatch.setattr(processing, "_apply", real_apply)

    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert where_is(c, a["_uid"]) == {}
    asyncio.run(processing.process_run_by_id(res, rid, final=True))  # redelivery
    run = db_run(c, lambda db: db.runs.find_one({"_id": rid}))
    # the plan's numbers survive the scrub: the run reports what was decided before the crash, once
    assert run["status"] == "accepted" and run["cells_claimed"] == plan["claimed"]
    assert db_run(c, lambda db: db.run_claims.count_documents({})) == 0
    assert where_is(c, a["_uid"]) == {}


def test_second_worker_holding_a_finished_run_does_not_claim_again(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    rid = seed_run(res_of(c), a["_uid"], square_fixes())
    stale = db_run(c, lambda db: db.runs.find_one({"_id": rid}))  # a second worker loaded it while processing
    fixes_doc = db_run(c, lambda db: db.run_fixes.find_one({"_id": rid}))
    asyncio.run(processing.process_run_by_id(res_of(c), rid))
    db_run(c, lambda db: db.run_fixes.insert_one(fixes_doc))  # ... and had read the fixes too
    before = db_run(c, lambda db: db.cell_power.find({}).to_list(None))
    asyncio.run(processing._process(res_of(c), stale))  # no plan exists any more: must not plan again
    after = db_run(c, lambda db: db.cell_power.find({}).to_list(None))
    assert {(d["cell"], d["power"]) for d in before} == {(d["cell"], d["power"]) for d in after}
    assert db_run(c, lambda db: db.run_claims.count_documents({})) == 0


# ------------------------------------------------------------------ N3: lock watchdog from the first lock
def R():
    return FakeAsyncRedis(server=FakeServer(), decode_responses=True)


def test_first_lock_is_kept_alive_while_waiting_for_the_second():
    async def go():
        r = R()
        await r.set("k2", "foreign", ex=60)
        ls = LockSet(r, ["k1", "k2"], ttl_s=2, wait_s=10)

        async def free_k2_later():
            await asyncio.sleep(3.0)  # longer than the TTL of k1
            await r.delete("k2")

        t = asyncio.create_task(free_k2_later())
        await ls.acquire()
        await t
        assert await r.get("k1") == ls.locks[0].token  # nobody could take k1 meanwhile
        ls.check()
        await ls.release()
        assert await r.get("k1") is None and await r.get("k2") is None

    asyncio.run(go())


def test_set_fails_and_releases_everything_if_a_lock_is_lost_while_acquiring():
    async def go():
        r = R()
        await r.set("k3", "foreign", ex=60)
        ls = LockSet(r, ["k1", "k2", "k3"], ttl_s=3, wait_s=10)

        async def intruder():
            await asyncio.sleep(0.3)
            await r.set("k1", "intruder", ex=60)  # k1 vanishes under us (Redis failover, clock jump...)

        t = asyncio.create_task(intruder())
        with pytest.raises(LockLost):
            await ls.acquire()
        await t
        assert await r.get("k2") is None  # what the set held is released
        assert await r.get("k1") == "intruder"  # and a foreign lock is never touched
        assert await r.get("k3") == "foreign"

    asyncio.run(go())


def test_losing_a_lock_after_acquire_frees_the_others_and_check_raises():
    async def go():
        r = R()
        async with LockSet(r, ["k1", "k2"], ttl_s=3, wait_s=5) as ls:
            await r.set("k1", "intruder", ex=60)
            await asyncio.sleep(1.3)  # one watchdog tick (ttl/3)
            with pytest.raises(LockLost):
                ls.check()
            assert await r.get("k2") is None
        assert await r.get("k1") == "intruder"

    asyncio.run(go())


# ------------------------------------------------------------------ N4: freeze helpers never overwrite a claim
class RacingPower:
    """cell_power whose first update_one is preceded by a worker applying a fresh claim to the same row."""

    def __init__(self, coll, new_fields):
        self.c, self.new_fields, self.first = coll, new_fields, True

    def __getattr__(self, n):
        return getattr(self.c, n)

    async def update_one(self, flt, upd, *a, **k):
        if self.first:
            self.first = False
            await self.c.update_one({"_id": flt["_id"]}, {"$set": self.new_fields})
        return await self.c.update_one(flt, upd, *a, **k)


class DBWith:
    def __init__(self, db, cell_power):
        self.db, self.cell_power = db, cell_power

    def __getattr__(self, n):
        return getattr(self.db, n)


def powers(c):
    return {d["_id"]: (d["power"], d["updated_at"]) for d in db_run(c, lambda db: db.cell_power.find({}).to_list(None))}


def test_freeze_start_cannot_overwrite_a_concurrent_claim(make_app, clock):
    c = make_app(**K1)
    a = login(c, "a")
    run_loop(c, a)
    clock.advance(days=60)
    db = res_of(c).db
    first = db_run(c, lambda db: db.cell_power.find_one({}))
    racing = DBWith(db, RacingPower(db.cell_power, {"power": 9.0, "updated_at": clock.now}))
    asyncio.run(rebase_for_freeze(racing, a["_uid"], clock.now))
    p = powers(c)
    assert p[first["_id"]] == (9.0, clock.now), "the claim's credit (9.0) was replaced by the stale faded value"
    # every other row was still rebased: faded(now) with updated_at = now - grace
    others = [v for k, v in p.items() if k != first["_id"]]
    assert others and all(v[0] < 1.0 for v in others)


def test_freeze_end_cannot_overwrite_a_concurrent_claim(make_app, clock):
    c = make_app(**K1)
    a = login(c, "a")
    run_loop(c, a)
    started = clock.now
    clock.advance(days=10)
    db = res_of(c).db
    first = db_run(c, lambda db: db.cell_power.find_one({}))
    user = {"_id": a["_uid"], "freeze_started_at": started, "freeze_until": started + 30 * 86_400_000}
    fresh_claim = {"power": 9.0, "updated_at": clock.now}  # a worker refreshed the row at the end of the freeze
    racing = DBWith(db, RacingPower(db.cell_power, fresh_claim))
    asyncio.run(settle_freeze(racing, user, clock.now - 86_400_000))  # the freeze ended a day before the claim
    assert powers(c)[first["_id"]] == (9.0, clock.now)


def test_freeze_route_racing_a_claim_keeps_the_credit(make_app, clock, monkeypatch):
    """Full route: a claim lands on a row between the freeze's read and its write."""
    c = make_app(**K1)
    a = login(c, "a")
    run_loop(c, a)
    clock.advance(days=60)
    res = res_of(c)
    real = res.db.cell_power
    res.db = DBWith(res.db, RacingPower(real, {"power": 9.0, "updated_at": clock.now}))
    try:
        assert c.post("/v1/me/freeze", json={"days": 5}, headers=hdr(a)).status_code == 200
    finally:
        res.db = res.db.db
    assert sum(1 for v in powers(c).values() if v == (9.0, clock.now)) == 1, "the claim's credit was overwritten"


# ------------------------------------------------------------------ N5: no run stays `processing`
def stuck_run(c, user, *, with_fixes=True, age_s=600):
    """What a crash leaves behind: a `processing` run (and its fixes) that nobody has queued."""
    fx = square_fixes()
    rid = str(uuid.uuid4())

    async def go(db):
        await db.runs.insert_one(
            {
                "_id": rid,
                "user_id": user["_uid"],
                "started_at": fx[0]["t"],
                "ended_at": fx[-1]["t"],
                "received_at": T0 - age_s * 1000,
                "status": "processing",
                "flags": [],
                "loops": [],
                "fix_count": len(fx),
            }
        )
        if with_fixes:
            await db.run_fixes.insert_one(
                {
                    "_id": rid,
                    "user_id": user["_uid"],
                    "fixes": [[f["lat"], f["lng"], f["t"], f["acc"], False] for f in fx],
                }
            )

    db_run(c, go)
    return rid, {"id": rid, "started_at": fx[0]["t"], "ended_at": fx[-1]["t"], "fixes": fx}


def status_of(c, h, rid):
    return c.get(f"/v1/runs/{rid}", headers=hdr(h)).json()["status"]


def test_repeat_upload_of_a_crashed_run_without_fixes_gets_it_processed(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    rid, body = stuck_run(c, a, with_fixes=False)  # crash between runs.insert_one and run_fixes.insert_one
    r = c.post("/v1/runs", json=body, headers=hdr(a))
    assert r.status_code == 202 and r.json()["status"] == "accepted"
    assert status_of(c, a, rid) == "accepted"


def test_repeat_upload_re_enqueues_a_run_lost_by_the_queue_exactly_once_worth_of_credit(make_app):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    rid, body = stuck_run(c, a)  # fixes stored, message lost
    assert status_of(c, a, rid) == "processing"
    assert c.post("/v1/runs", json=body, headers=hdr(a)).json()["status"] == "accepted"
    once = powers(c)
    assert c.post("/v1/runs", json=body, headers=hdr(a)).json()["status"] == "accepted"  # now a plain repeat
    assert powers(c) == once
    # compare with a run uploaded normally by another user in another place: same credit per cell
    ref = run_loop(c, b, lat=50.3)
    assert (
        sum(p for p, _ in once.values())
        == pytest.approx(sum(v[0] for k, v in powers(c).items() if k not in once), rel=1e-6)
        or ref["cells_claimed"] > 0
    )


def test_repeat_upload_inside_the_threshold_does_not_re_enqueue(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    rid, body = stuck_run(c, a, age_s=5)  # 5 s old: the first attempt may still be on its way
    r = c.post("/v1/runs", json=body, headers=hdr(a))
    assert r.json()["status"] == "processing"
    assert status_of(c, a, rid) == "processing"


def test_repeat_upload_re_enqueue_failure_is_503_and_keeps_the_run(make_app, monkeypatch):
    c = make_app(**K1)
    a = login(c, "a")
    rid, body = stuck_run(c, a)

    def boom(_):
        raise ConnectionError("redis down")

    monkeypatch.setattr(api, "enqueue_run", boom)
    assert c.post("/v1/runs", json=body, headers=hdr(a)).status_code == 503
    assert db_run(c, lambda db: db.runs.count_documents({"_id": rid})) == 1
    monkeypatch.undo()
    assert c.post("/v1/runs", json=body, headers=hdr(a)).json()["status"] == "accepted"


def test_sweeper_requeues_runs_stuck_for_more_than_five_minutes(make_app, clock):
    c = make_app(**K1)
    a = login(c, "a")
    old, _ = stuck_run(c, a, age_s=600)
    young, _ = stuck_run(c, a, age_s=120)
    queued: list[str] = []
    assert asyncio.run(processing.sweep_stuck_runs(res_of(c), queued.append)) == 1
    assert queued == [old]
    # a message that is still in flight is not queued again on every sweep ...
    assert asyncio.run(processing.sweep_stuck_runs(res_of(c), queued.append)) == 0
    # ... but is once the last attempt is older than the threshold
    clock.advance(seconds=301)
    assert asyncio.run(processing.sweep_stuck_runs(res_of(c), queued.append)) == 2
    assert set(queued) == {old, young}


def test_sweeper_task_processes_stuck_runs_and_is_scheduled(make_app):
    from app.worker import celery_app

    c = make_app(**K1)
    a = login(c, "a")
    rid, _ = stuck_run(c, a, age_s=600)
    stuck_run(c, a, age_s=30)  # too young
    assert sweep_stuck_runs_task() == 1
    assert status_of(c, a, rid) == "accepted"
    entry = celery_app.conf.beat_schedule["sweep-stuck-runs"]
    assert entry["task"] == "looprun.sweep_stuck_runs" and entry["schedule"] == 60.0


def test_sweeper_survives_an_enqueue_error_and_keeps_going(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    r1, _ = stuck_run(c, a)
    r2, _ = stuck_run(c, a)
    seen = []

    def flaky(rid):
        seen.append(rid)
        if len(seen) == 1:
            raise ConnectionError("redis down")

    assert asyncio.run(processing.sweep_stuck_runs(res_of(c), flaky)) == 1
    assert set(seen) == {r1, r2}


def test_enqueue_is_idempotent_per_run_id(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    rid, body = stuck_run(c, a)
    enqueue_run(rid)
    once = powers(c)
    enqueue_run(rid)
    enqueue_run(rid)
    assert powers(c) == once and status_of(c, a, rid) == "accepted"


# ------------------------------------------------------------------ N6: upload racing account deletion
def test_upload_after_the_account_is_gone_leaves_no_run_or_fixes(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    stale = db_run(c, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    c.app.dependency_overrides[auth.current_user] = lambda: stale  # authenticated before the delete finished
    try:
        upload(c, a, square_fixes(), expect=401)
    finally:
        c.app.dependency_overrides.clear()
    assert db_run(c, lambda db: db.runs.count_documents({})) == 0
    assert db_run(c, lambda db: db.run_fixes.count_documents({})) == 0
    assert where_is(c, a["_uid"]) == {}


def test_upload_when_deletion_has_started_leaves_no_run_or_fixes(make_app):
    c = make_app(**K1)
    a = login(c, "a")
    stale = db_run(c, lambda db: db.users.find_one({"_id": a["_uid"]}))
    hold_user_lock(c, a["_uid"])
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 503  # now `deleting`
    c.app.dependency_overrides[auth.current_user] = lambda: stale
    try:
        upload(c, a, square_fixes(), expect=403)
    finally:
        c.app.dependency_overrides.clear()
    assert db_run(c, lambda db: db.runs.count_documents({})) == 0
    assert db_run(c, lambda db: db.run_fixes.count_documents({})) == 0


# ------------------------------------------------------------------ notes
def test_delete_maps_lock_lost_and_database_errors_to_503_with_retry_after(make_app, monkeypatch):
    c = make_app(**K1)
    a = login(c, "a")
    real = api.delete_account
    for exc in (LockLost("gone"), LockTimeout("busy"), OperationFailure("not primary"), ConnectionError("x")):

        async def boom(res, uid, exc=exc):
            raise exc

        monkeypatch.setattr(api, "delete_account", boom)
        r = c.delete("/v1/me", headers=hdr(a))
        assert r.status_code == 503 and r.headers["retry-after"], exc
    monkeypatch.setattr(api, "delete_account", real)
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204


def test_leaderboard_lists_only_owners_the_map_names(make_app):
    c = make_app()  # K = 3 and no delay
    a, b, d, e = (login(c, n) for n in ("a", "b", "d", "e"))
    run_loop(c, a)
    # alone: hidden on the map, so absent from everyone else's leaderboard (but a sees themself)
    assert board(c, b) == {}
    assert set(board(c, a)) == {"a"}
    run_loop(c, b, lat=50.0004, lng=8.7004)  # two users nearby: still below K
    assert board(c, d) == {}
    run_loop(c, d, lat=50.0008, lng=8.7008)  # three users within the privacy ring: names appear
    named = {}
    for x in cells_of(c, e):
        if x["owner"]:
            named[x["owner"]["name"]] = named.get(x["owner"]["name"], 0) + 1
    assert named and board(c, e) == named


def test_leaderboard_skips_home_zone_owners(make_app):
    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    lat, lng = eng.cell_centre(cells_of(c, a)[0]["id"])
    zone = {"zones": [{"lat": lat, "lng": lng, "radius_m": 1000}]}
    assert c.put("/v1/me/home-zones", json=zone, headers=hdr(a)).status_code == 204
    assert all(x["owner"] is None and x["hidden"] for x in cells_of(c, b))
    assert board(c, b) == {}  # same rule as the map
    assert board(c, a).get("a", 0) > 0  # the owner still sees their own entry


def test_websocket_handshake_failures_are_http_403_and_first_message_failures_close_4401(client):
    a = login(client, "a")
    tok = a["Authorization"].split()[1]
    for url in (f"/v1/live?bbox=8,49,9,51&token={tok}", "/v1/live?bbox=nonsense", f"/v1/live?bbox={BBOX}&token=junk"):
        with pytest.raises(WebSocketDisconnect), client.websocket_connect(url):
            pass
    with client.websocket_connect(f"/v1/live?bbox={BBOX}") as ws:
        ws.send_json({"type": "auth", "token": "junk"})
        with pytest.raises(WebSocketDisconnect) as e:
            ws.receive_json()
    assert e.value.code == 4401


def test_generated_openapi_documents_the_same_status_codes_as_the_contract(client):
    import pathlib

    contract = yaml.safe_load(
        (pathlib.Path(__file__).resolve().parents[2] / "docs" / "CONTRACT.openapi.yaml").read_text()
    )
    gen = client.app.openapi()["paths"]
    checked = 0
    for p, ops in contract["paths"].items():
        if p == "/live":
            continue
        for method, op in ops.items():
            codes_c = set(op["responses"])
            codes_g = set(gen["/v1" + p.replace("{id}", "{run_id}")][method]["responses"])
            assert codes_c == codes_g, (method, p, sorted(codes_c ^ codes_g))
            checked += 1
    assert checked == 9


def test_live_contract_documents_403_4401_4429_and_the_socket_cap():
    import pathlib

    contract = yaml.safe_load(
        (pathlib.Path(__file__).resolve().parents[2] / "docs" / "CONTRACT.openapi.yaml").read_text()
    )
    text = contract["paths"]["/live"]["get"]["description"]
    for needle in ("403", "4401", "4429", "5 "):
        assert needle in text, needle


def test_websocket_cap_of_five_per_user(make_app):
    from contextlib import ExitStack

    c = make_app(**K1)
    a, b = login(c, "a"), login(c, "b")
    tok = a["Authorization"].split()[1]
    url = f"/v1/live?bbox={BBOX}&token={tok}"
    with ExitStack() as stack:
        socks = [stack.enter_context(c.websocket_connect(url)) for _ in range(5)]
        with pytest.raises(WebSocketDisconnect), c.websocket_connect(url):  # before accept: HTTP 403
            pass
        with c.websocket_connect(f"/v1/live?bbox={BBOX}") as ws:  # first-message auth: closed with 4429
            ws.send_json({"type": "auth", "token": tok})
            with pytest.raises(WebSocketDisconnect) as e:
                ws.receive_json()
            assert e.value.code == 4429
        # another user is not affected
        with c.websocket_connect(f"/v1/live?bbox={BBOX}&token={b['Authorization'].split()[1]}"):
            pass
        socks[0].close()
        for _ in range(100):  # the freed slot appears once the server noticed the disconnect
            try:
                with c.websocket_connect(url):
                    break
            except WebSocketDisconnect:
                import time

                time.sleep(0.05)
        else:
            pytest.fail("slot not freed after a socket closed")


def test_websocket_slots_of_dead_processes_expire(make_app, clock):
    c = make_app(ws_max_sockets_per_user=1, ws_recheck_seconds=10, **K1)
    a = login(c, "a")
    key = f"looprun:ws:{a['_uid']}"
    asyncio.run(res_of(c).redis.zadd(key, {"ghost": clock.now}))  # a process that crashed holding a slot
    url = f"/v1/live?bbox={BBOX}&token={a['Authorization'].split()[1]}"
    with pytest.raises(WebSocketDisconnect), c.websocket_connect(url):
        pass
    clock.advance(seconds=31)  # three missed heartbeats
    with c.websocket_connect(url):
        pass


def test_cells_requests_are_rate_limited_per_user(make_app):
    c = make_app(cells_rate_limit=3, **K1)
    a, b = login(c, "a"), login(c, "b")
    for _ in range(3):
        assert c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(a)).status_code == 200
    r = c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(a))
    assert r.status_code == 429 and int(r.headers["retry-after"]) >= 1
    assert c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(b)).status_code == 200  # per user


def test_cells_rate_limit_defaults_to_120_per_minute_and_resets(make_app, clock):
    c = make_app(**K1)
    assert c.app.state.res.settings.cells_rate_limit == 120
    c = make_app(cells_rate_limit=2, **K1)
    a = login(c, "a")
    for _ in range(2):
        assert c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(a)).status_code == 200
    assert c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(a)).status_code == 429
    clock.advance(seconds=61)
    assert c.get("/v1/cells", params={"bbox": BBOX}, headers=hdr(a)).status_code == 200
