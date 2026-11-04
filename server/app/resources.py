"""Connections (Mongo, Redis) and the clock, bundled so tests can swap them for fakes."""

from __future__ import annotations

import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

from .config import Settings


def system_clock() -> int:
    """Epoch milliseconds."""
    return int(time.time() * 1000)


@dataclass
class Resources:
    settings: Settings
    db: Any  # motor / mongomock-motor database
    redis: Any  # redis.asyncio.Redis / fakeredis.aioredis.FakeRedis
    clock: Callable[[], int] = system_clock
    closers: list[Callable[[], Awaitable[None]]] = field(default_factory=list)

    async def close(self) -> None:
        for c in self.closers:
            try:
                await c()
            except Exception:  # noqa: BLE001 - closing must never raise
                pass


def build_resources(settings: Settings) -> Resources:
    from motor.motor_asyncio import AsyncIOMotorClient  # noqa: PLC0415
    from redis.asyncio import from_url  # noqa: PLC0415

    mongo = AsyncIOMotorClient(settings.mongo_url, tz_aware=True)
    try:
        db = mongo.get_default_database()
    except Exception:  # noqa: BLE001 - URL without a database name
        db = mongo[settings.mongo_db]
    redis = from_url(settings.redis_url, decode_responses=True)

    async def close_redis() -> None:
        await redis.aclose()

    async def close_mongo() -> None:
        mongo.close()

    return Resources(settings=settings, db=db, redis=redis, closers=[close_redis, close_mongo])


# Tests install a factory returning fakes; production uses build_resources.
_factory: Callable[[Settings], Resources] | None = None


def set_resource_factory(factory: Callable[[Settings], Resources] | None) -> None:
    global _factory
    _factory = factory


def make_resources(settings: Settings) -> Resources:
    return (_factory or build_resources)(settings)


async def ensure_indexes(db: Any) -> None:
    await db.users.create_index("google_sub", unique=True)
    await db.runs.create_index("user_id")
    await db.run_fixes.create_index("user_id")
    # Raw GPS: documents with an `expire_at` date are deleted by Mongo's TTL monitor at that time.
    await db.run_fixes.create_index("expire_at", expireAfterSeconds=0)
    await db.run_claims.create_index("user_id")
    await db.run_claims.create_index("refs")
    await db.run_claims.create_index("expire_at", expireAfterSeconds=0)
    await db.runs.create_index([("status", 1), ("received_at", 1)])
    await db.cell_power.create_index([("cell", 1), ("user_id", 1)], unique=True)
    await db.cell_power.create_index("user_id")
    await db.cells.create_index([("lat", 1), ("lng", 1)])
    await db.cells.create_index("owner_id")
    await db.cells.create_index("public_owner_id")
    await db.cells.create_index("pending_owner_id")
    await db.reports.create_index("expire_at", expireAfterSeconds=0)
    await db.reports.create_index("reporter_id")
