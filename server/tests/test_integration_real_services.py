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
