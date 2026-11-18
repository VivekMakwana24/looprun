"""Helpers shared by the Phase 1a tests (docs/PHASE1_SPEC.md): direct seeding of social data and read helpers."""

from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

from .conftest import T0, db_run, hdr, login, square_fixes, upload

K1 = {"privacy_min_users": 1}
HOUR = 3_600_000
DAY = 86_400_000


def res_of(c):
    return c.app.state.res


def users(c, *names):
    return [login(c, n) for n in names]


def uid(h):
    return h["_uid"]


def get(c, h, path, **params):
    return c.get(f"/v1{path}", params=params, headers=hdr(h))


def put(c, h, path, **kw):
    return c.put(f"/v1{path}", headers=hdr(h), **kw)


def post(c, h, path, json=None):
    return c.post(f"/v1{path}", json=json, headers=hdr(h))


def delete(c, h, path):
    return c.delete(f"/v1{path}", headers=hdr(h))


def patch(c, h, path, json=None):
    return c.patch(f"/v1{path}", json=json, headers=hdr(h))


def ins(c, coll, *docs):
    async def go(db):
        for d in docs:
            await db[coll].insert_one(d)

    db_run(c, go)


def find(c, coll, q=None):
    async def go(db):
        return [d async for d in db[coll].find(q or {})]

    return db_run(c, go)


def count(c, coll, q=None):
    return db_run(c, lambda db: db[coll].count_documents(q or {}))


def upd(c, coll, q, change):
    return db_run(c, lambda db: db[coll].update_many(q, change))


def follow(c, a, b):
    r = put(c, a, f"/users/{uid(b)}/follow")
    assert r.status_code == 200, r.text
    return r


def seed_run(c, owner, *, at, claimed=("c1",), status="accepted", cells_taken=0, distance=5000.0, moving=1500, **extra):
    """Insert an accepted run document directly. `at` is processed_at (epoch ms)."""
    rid = str(uuid.uuid4())
    doc = {
        "_id": rid,
        "user_id": uid(owner),
        "started_at": at - 3_600_000,
        "ended_at": at - 1_800_000,
        "received_at": at - 1000,
        "status": status,
        "distance_m": distance,
        "moving_seconds": moving,
        "loops": [{"cells": len(claimed), "area_km2": 0.1}],
        "cells_claimed": len(claimed) if status == "accepted" else 0,
        "cells_taken_from_others": cells_taken,
        "flags": [],
        "cells": list(claimed),
        "processed_at": at,
        "claimed_cells": list(claimed),
        "integrity_token": "secret-token",
    }
    doc.update(extra)
    ins(c, "runs", doc)
    return rid


def seed_event(c, run_id, cell, taker, victim, *, at, k_ok=True):
    ins(
        c,
        "battle_events",
        {
            "_id": f"{run_id}:{cell}",
            "run_id": run_id,
            "cell": cell,
            "at": at,
            "taker_id": uid(taker) if isinstance(taker, dict) else taker,
            "victim_id": (uid(victim) if isinstance(victim, dict) else victim),
            "k_ok": k_ok,
            "expire_at": datetime.fromtimestamp(at / 1000, UTC) + timedelta(days=90),
        },
    )


__all__ = ["T0", "asyncio", "hdr", "login", "square_fixes", "upload"]
