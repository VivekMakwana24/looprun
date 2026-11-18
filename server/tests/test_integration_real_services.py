"""Smoke test against REAL MongoDB and Redis (everything else in server/tests uses fakes).

Skipped unless LOOPRUN_MONGO_URL and LOOPRUN_REDIS_URL are both set. CI runs it in the `integration` job with
service containers. It drops the Mongo database named in the URL, so it refuses to run unless that name
contains "test". Run locally:

    LOOPRUN_MONGO_URL=mongodb://localhost:27017/looprun_test LOOPRUN_REDIS_URL=redis://localhost:6379/15 \
        pytest server -m integration -o addopts=""
"""

from __future__ import annotations

import os
import time
import uuid

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

from .conftest import cells_of, hdr, login, square_fixes, upload

MONGO_URL = os.environ.get("LOOPRUN_MONGO_URL", "")
REDIS_URL = os.environ.get("LOOPRUN_REDIS_URL", "")

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not (MONGO_URL and REDIS_URL), reason="LOOPRUN_MONGO_URL and LOOPRUN_REDIS_URL not set"),
]


@pytest.fixture
def real_db():
    from pymongo import MongoClient  # noqa: PLC0415

    mc = MongoClient(MONGO_URL, tz_aware=True, serverSelectionTimeoutMS=10_000)
    try:
        db = mc.get_default_database()
    except Exception:  # noqa: BLE001 - URL without a database name
        db = mc["looprun"]
    if "test" not in db.name:
        pytest.fail(f"refusing to drop database {db.name!r}: its name must contain 'test'")
    mc.drop_database(db.name)
    yield db
    mc.drop_database(db.name)
    mc.close()


def test_real_mongo_and_redis_end_to_end(real_db):
    settings = Settings(
        dev_auth=True,
        jwt_secret="integration-secret-integration-secret-32b",
        mongo_url=MONGO_URL,
        redis_url=REDIS_URL,
        publish_delay_seconds=0,
        celery_task_always_eager=True,
        run_rate_limit=1000,
        leaderboard_cache_seconds=0,
    )
    # No resource factory is installed, so create_app builds real Motor and Redis clients.
    with TestClient(create_app(settings)) as client:
        # 1. dev-auth login
        h = login(client, f"it{uuid.uuid4().hex[:8]}")

        # 2. upload one run (recent timestamps: this uses the real clock) and read its status
        t0 = int(time.time() * 1000) - 3_600_000
        rid, _ = upload(client, h, square_fixes(t0=t0))
        r = client.get(f"/v1/runs/{rid}", headers=hdr(h))
        assert r.status_code == 200, r.text
        run = r.json()
        assert run["status"] == "accepted", run
        assert run["cells_claimed"] > 0

        # 3. cells read: the runner sees their own cells
        cells = cells_of(client, h)
        assert cells, "expected claimed cells in the bounding box"
        assert any(c["mine"] for c in cells)

        # 4. TTL indexes exist (raw GPS 30 days / reports 180 days are enforced by Mongo's TTL monitor)
        for coll in ("run_fixes", "reports"):
            ttl = [i for i in real_db[coll].list_indexes() if "expireAfterSeconds" in i]
            assert any(list(i["key"]) == ["expire_at"] and i["expireAfterSeconds"] == 0 for i in ttl), (coll, ttl)

        # 5. accepted runs keep no raw GPS
        assert real_db.run_fixes.count_documents({"_id": rid}) == 0

        # 6. delete account: user, runs and cell power are gone; cells nobody else holds are freed
        assert client.delete("/v1/me", headers=hdr(h)).status_code == 204
        assert real_db.users.count_documents({}) == 0
        assert real_db.runs.count_documents({}) == 0
        assert real_db.cell_power.count_documents({}) == 0
        assert not any(c.get("owner_id") for c in real_db.cells.find({}))


def _real_client():
    settings = Settings(
        dev_auth=True,
        jwt_secret="integration-secret-integration-secret-32b",
        mongo_url=MONGO_URL,
        redis_url=REDIS_URL,
        publish_delay_seconds=0,
        celery_task_always_eager=True,
        run_rate_limit=1000,
        leaderboard_cache_seconds=0,
    )
    return TestClient(create_app(settings))


def _ttl(db, coll):
    return [i for i in db[coll].list_indexes() if "expireAfterSeconds" in i]


def test_real_mongo_phase1a_battle_events_and_indexes(real_db):
    with _real_client() as client:
        a = login(client, f"ia{uuid.uuid4().hex[:6]}")
        b = login(client, f"ib{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        upload(client, a, square_fixes(t0=t0, speed=3.0))
        rid, _ = upload(client, b, square_fixes(t0=t0 + 3_600_000, speed=1.5))
        run_b = client.get(f"/v1/runs/{rid}", headers=hdr(b)).json()
        assert run_b["cells_taken_from_others"] > 0

        # one battle row per flipped cell, keyed run:cell; TTL index on expire_at (0 s)
        rows = list(real_db.battle_events.find({}))
        assert len(rows) == run_b["cells_taken_from_others"]
        assert all(r["_id"] == f"{r['run_id']}:{r['cell']}" and r["victim_id"] != r["taker_id"] for r in rows)
        ttl = _ttl(real_db, "battle_events")
        assert any(list(i["key"]) == ["expire_at"] and i["expireAfterSeconds"] == 0 for i in ttl), ttl
        # claimed cells are stored on the accepted run (never returned by the API)
        assert len(real_db.runs.find_one({"_id": rid})["claimed_cells"]) == run_b["cells_claimed"]
        # the indexes of docs/PHASE1_SPEC.md 0.6 that serve the claim pipeline
        keys = {tuple(i["key"].keys()) for i in real_db.battle_events.list_indexes()}
        assert {("victim_id", "at"), ("taker_id", "at"), ("run_id",)} <= keys
        run_keys = {tuple(i["key"].keys()) for i in real_db.runs.list_indexes()}
        assert ("user_id", "status", "processed_at", "_id") in run_keys
        assert ("user_id", "started_at", "_id") in run_keys


def test_real_mongo_profile_rename_and_follow_indexes(real_db):
    with _real_client() as client:
        a = login(client, f"pa{uuid.uuid4().hex[:6]}")
        b = login(client, f"pb{uuid.uuid4().hex[:6]}")
        r = client.patch("/v1/me", json={"display_name": "  Mia   K "}, headers=hdr(a))
        assert r.status_code == 200 and r.json()["user"]["name"] == "Mia K"
        assert real_db.users.find_one({"_id": a["_uid"]})["name_lower"] == "mia k"
        profile = client.get(f"/v1/users/{a['_uid']}", headers=hdr(b))
        assert profile.status_code == 200 and profile.json()["name"] == "Mia K"
        follows = {i["name"]: i for i in real_db.follows.list_indexes()}
        uniq = [i for i in follows.values() if i.get("unique")]
        assert [list(i["key"]) for i in uniq] == [["follower_id", "followee_id"]]
        assert "name_lower_1" in {i["name"] for i in real_db.users.list_indexes()}


def test_real_mongo_follow_search_notifications(real_db):
    with _real_client() as client:
        tag = uuid.uuid4().hex[:5]
        a, b = login(client, f"fa{tag}"), login(client, f"fb{tag}")
        for _ in range(2):  # idempotent: the unique index and the upsert agree
            r = client.put(f"/v1/users/{b['_uid']}/follow", headers=hdr(a))
            assert r.status_code == 200 and r.json() == {"is_following": True, "followers_count": 1}
        assert real_db.follows.count_documents({}) == 1 and real_db.notifications.count_documents({}) == 1
        got = client.get("/v1/users/search", params={"q": f"FB{tag}"[:4]}, headers=hdr(a)).json()["users"]
        assert [u["id"] for u in got] == [b["_uid"]]
        assert client.get("/v1/me/following", headers=hdr(a)).json()["items"][0]["id"] == b["_uid"]
        ttl = _ttl(real_db, "notifications")
        assert any(list(i["key"]) == ["expire_at"] and i["expireAfterSeconds"] == 0 for i in ttl), ttl
        assert client.put(f"/v1/users/{a['_uid']}/follow", headers=hdr(a)).json()["detail"]["code"] == "self"


def test_real_mongo_feed_history_and_battle_cards(real_db):
    with _real_client() as client:
        a = login(client, f"ea{uuid.uuid4().hex[:6]}")
        b = login(client, f"eb{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        upload(client, a, square_fixes(t0=t0, speed=3.0))
        rid, _ = upload(client, b, square_fixes(t0=t0 + 3_600_000, speed=1.5))
        assert client.put(f"/v1/users/{a['_uid']}/follow", headers=hdr(b)).status_code == 200
        own = client.get("/v1/runs", headers=hdr(b)).json()["items"]
        assert [c["id"] for c in own] == [rid] and own[0]["cells_claimed"] > 0 and own[0]["status"] == "accepted"
        # the real publish delay (30 min) has not passed for the card of a run that finished just now; own runs show
        feed = client.get("/v1/feed", headers=hdr(b)).json()["items"]
        assert rid in [c["id"] for c in feed]
        # alice's first run is two hours old: bob follows her, so it is in his feed after the delay
        a_run = real_db.runs.find_one({"user_id": a["_uid"]})
        assert a_run["_id"] in [c["id"] for c in feed] and "claimed_cells" in a_run
        keys = {tuple(i["key"].keys()) for i in real_db.runs.list_indexes()}
        assert ("user_id", "status", "processed_at", "_id") in keys


def test_real_mongo_kudos_and_comments_counts_on_cards(real_db):
    with _real_client() as client:
        a = login(client, f"ka{uuid.uuid4().hex[:6]}")
        b = login(client, f"kb{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        rid, _ = upload(client, b, square_fixes(t0=t0))
        assert client.put(f"/v1/users/{b['_uid']}/follow", headers=hdr(a)).status_code == 200
        # the real publish delay: the run finished just now, so alice cannot see it yet (404, like an unknown run)
        assert client.put(f"/v1/runs/{rid}/kudos", headers=hdr(a)).status_code == 404
        real_db.runs.update_one({"_id": rid}, {"$set": {"processed_at": int(time.time() * 1000) - 3_600_000}})
        assert client.put(f"/v1/runs/{rid}/kudos", headers=hdr(a)).json() == {"kudos_by_me": True, "kudos_count": 1}
        c = client.post(f"/v1/runs/{rid}/comments", json={"text": "  nice loop "}, headers=hdr(a))
        assert c.status_code == 201 and c.json()["text"] == "nice loop"
        card = next(x for x in client.get("/v1/feed", headers=hdr(a)).json()["items"] if x["id"] == rid)
        assert (card["kudos_count"], card["kudos_by_me"], card["comment_count"]) == (1, True, 1)
        assert real_db.notifications.count_documents({"type": {"$in": ["kudos", "comment"]}}) == 2
        assert client.delete(f"/v1/runs/{rid}/comments/{c.json()['id']}", headers=hdr(b)).status_code == 204
        assert real_db.comments.count_documents({}) == 0


def test_real_mongo_battles_from_a_real_takeover(real_db):
    with _real_client() as client:
        a = login(client, f"ba{uuid.uuid4().hex[:6]}")
        b = login(client, f"bb{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        upload(client, a, square_fixes(t0=t0, speed=3.0))
        rid, _ = upload(client, b, square_fixes(t0=t0 + 3_600_000, speed=1.5))
        n = client.get(f"/v1/runs/{rid}", headers=hdr(b)).json()["cells_taken_from_others"]
        assert n > 0
        # events younger than the real 30-minute delay are not visible to anybody yet
        assert client.get("/v1/battles/summary", headers=hdr(a)).json()["lost"] == 0
        real_db.battle_events.update_many({}, {"$set": {"at": int(time.time() * 1000) - 3_600_000}})
        sa = client.get("/v1/battles/summary", headers=hdr(a)).json()
        sb = client.get("/v1/battles/summary", headers=hdr(b)).json()
        assert (sa["lost"], sa["battles"], sb["taken"]) == (n, 1, n)
        back = client.get("/v1/battles/take-back", headers=hdr(a)).json()["cells"]
        assert len(back) == n and all(len(c["boundary"]) in (5, 6) for c in back)
        rv = client.get("/v1/battles/rivalry", headers=hdr(a)).json()
        assert rv["unattributed"]["lost"] + sum(r["lost"] for r in rv["rivals"]) == n  # K-anonymity decides which


def test_real_mongo_notifications_inbox_and_mark_read(real_db):
    with _real_client() as client:
        a = login(client, f"na{uuid.uuid4().hex[:6]}")
        b = login(client, f"nb{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        upload(client, a, square_fixes(t0=t0, speed=3.0))
        rid, _ = upload(client, b, square_fixes(t0=t0 + 3_600_000, speed=1.5))
        assert client.put(f"/v1/users/{a['_uid']}/follow", headers=hdr(b)).status_code == 200
        assert real_db.notifications.count_documents({"type": "cells_taken"}) == 1
        # nothing is visible before visible_at (the real publish delay)
        before = client.get("/v1/notifications", headers=hdr(a)).json()
        assert before == {"items": [], "next_cursor": None, "unread_count": 0}
        real_db.notifications.update_many({}, {"$set": {"visible_at": int(time.time() * 1000) - 1000}})
        page = client.get("/v1/notifications", headers=hdr(a)).json()
        assert {i["type"] for i in page["items"]} == {"cells_taken", "new_follower"} and page["unread_count"] == 2
        assert rid not in str(page)
        mine = [i["id"] for i in page["items"]]
        assert client.post("/v1/notifications/read", json={"ids": mine[:1]}, headers=hdr(a)).status_code == 204
        assert client.get("/v1/notifications/unread-count", headers=hdr(a)).json() == {"unread_count": 1}
        assert client.post("/v1/notifications/read", json={"all": True}, headers=hdr(a)).status_code == 204
        assert client.get("/v1/notifications/unread-count", headers=hdr(a)).json() == {"unread_count": 0}


def test_real_mongo_block_report_unique_index_and_moderation_log_ttl(real_db):
    import asyncio

    from app import moderation  # noqa: PLC0415
    from app.resources import build_resources  # noqa: PLC0415

    with _real_client() as client:
        a = login(client, f"ma{uuid.uuid4().hex[:6]}")
        b = login(client, f"mb{uuid.uuid4().hex[:6]}")
        assert client.put(f"/v1/users/{b['_uid']}/follow", headers=hdr(a)).status_code == 200
        for _ in range(2):  # the same report twice: 202 both times, one row (unique partial index)
            r = client.post(
                "/v1/reports", json={"kind": "user", "target_id": b["_uid"], "reason": "x"}, headers=hdr(a)
            )
            assert r.status_code == 202
        assert real_db.reports.count_documents({"kind": "user"}) == 1
        for _ in range(2):  # old kinds are not deduplicated
            client.post("/v1/reports", json={"kind": "cell", "target_id": "c", "reason": "x"}, headers=hdr(a))
        assert real_db.reports.count_documents({"kind": "cell"}) == 2
        idx = [i for i in real_db.reports.list_indexes() if i.get("unique")]
        assert idx and idx[0]["partialFilterExpression"] == {"kind": {"$in": ["user", "comment", "run_card"]}}
        # block: follows go, the row stays, profile is 404 both ways
        assert client.put(f"/v1/users/{a['_uid']}/block", headers=hdr(b)).status_code == 204
        assert real_db.follows.count_documents({}) == 0 and real_db.blocks.count_documents({}) == 1
        assert client.get(f"/v1/users/{b['_uid']}", headers=hdr(a)).status_code == 404
        # moderation CLI against the real database, then the TTL index of its log
        async def hide() -> list[str]:  # one event loop for the Motor client: build, run, close
            res = build_resources(Settings(mongo_url=MONGO_URL, redis_url=REDIS_URL))
            try:
                return await moderation.execute(res, ["hide-name", b["_uid"]], admin="ci")
            finally:
                await res.close()

        lines = asyncio.run(hide())
        assert "ok" in lines[0] and real_db.users.find_one({"_id": b["_uid"]})["name_hidden"] is True
        assert real_db.reports.find_one({"kind": "user"})["state"] == "hidden"
        assert real_db.moderation_log.count_documents({"admin": "ci"}) == 1
        ttl = _ttl(real_db, "moderation_log")
        assert any(list(i["key"]) == ["expire_at"] and i["expireAfterSeconds"] == 0 for i in ttl), ttl


def test_real_mongo_delete_me_cleans_all_phase1a_data(real_db):
    with _real_client() as client:
        a = login(client, f"da{uuid.uuid4().hex[:6]}")
        b = login(client, f"db{uuid.uuid4().hex[:6]}")
        t0 = int(time.time() * 1000) - 7_200_000
        upload(client, a, square_fixes(t0=t0, speed=3.0))
        rid, _ = upload(client, b, square_fixes(t0=t0 + 3_600_000, speed=1.5))
        assert client.put(f"/v1/users/{a['_uid']}/follow", headers=hdr(b)).status_code == 200
        assert client.put(f"/v1/users/{b['_uid']}/follow", headers=hdr(a)).status_code == 200
        assert client.post(
            "/v1/reports", json={"kind": "user", "target_id": a["_uid"], "reason": "x"}, headers=hdr(b)
        ).status_code == 202
        assert real_db.battle_events.count_documents({"victim_id": a["_uid"]}) > 0
        assert client.delete("/v1/me", headers=hdr(a)).status_code == 204
        for coll in ("follows", "kudos", "comments", "notifications", "blocks"):
            assert real_db[coll].count_documents({}) == 0, coll
        # bob's takes stay as anonymous history; alice no longer appears in any battle row
        assert real_db.battle_events.count_documents({"$or": [{"taker_id": a["_uid"]}, {"victim_id": a["_uid"]}]}) == 0
        assert real_db.battle_events.count_documents({"taker_id": b["_uid"], "victim_id": None}) > 0
        assert real_db.reports.count_documents({"target_id": a["_uid"]}) == 1  # reports about her stay
        assert client.get(f"/v1/runs/{rid}", headers=hdr(b)).status_code == 200
