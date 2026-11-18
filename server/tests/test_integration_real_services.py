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
