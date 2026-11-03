"""Run processing: engine -> cells, cell power and ownership. Called by the Celery task."""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any

from . import engine_adapter as eng
from .cellview import change_fields
from .events import invalidate_leaderboard, publish_changes
from .freeze import settle_expired
from .resources import Resources

log = logging.getLogger("looprun.processing")

LOCK_KEY = "looprun:lock:claims"


async def _acquire(redis: Any, ttl_s: int, wait_s: float = 60.0) -> str:
    token = uuid.uuid4().hex
    waited = 0.0
    while not await redis.set(LOCK_KEY, token, nx=True, ex=ttl_s):
        if waited >= wait_s:
            raise TimeoutError("could not acquire the claims lock")
        await asyncio.sleep(0.05)
        waited += 0.05
    return token


async def _release(redis: Any, token: str) -> None:
    if await redis.get(LOCK_KEY) == token:
        await redis.delete(LOCK_KEY)


async def active_freezes(db: Any, user_ids: set[str], now: int) -> dict[str, int]:
    out: dict[str, int] = {}
    if not user_ids:
        return out
    async for u in db.users.find({"_id": {"$in": sorted(user_ids)}}, {"freeze_until": 1}):
        fu = u.get("freeze_until")
        if fu and fu > now:
            out[u["_id"]] = fu
    return out


async def process_run_by_id(res: Resources, run_id: str) -> None:
    db = res.db
    run = await db.runs.find_one({"_id": run_id})
    if run is None or run.get("status") != "processing":
        return  # unknown, or already processed (task redelivered): nothing to do
    try:
        processed = eng.process_run(run["fixes"])
    except Exception:  # noqa: BLE001
        log.exception("engine_failed", extra={"run_id": run_id})
        await db.runs.update_one(
            {"_id": run_id},
            {
                "$set": {
                    "status": "rejected",
                    "flags": [{"code": "processing_error", "severity": "hard", "detail": "engine error"}],
                }
            },
        )
        return

    claimed = taken = 0
    changes: list[dict] = []
    if processed.cells:
        claimed, taken, changes = await _claim_cells(res, run, processed)

    excluded = any(f["code"] == "implausible_loop" for f in processed.flags)
    needs_review = processed.status != "accepted" or excluded
    update: dict[str, Any] = {
        "status": processed.status,
        "distance_m": processed.distance_m,
        "moving_seconds": processed.moving_seconds,
        "loops": processed.loops,
        "flags": processed.flags,
        "cells": processed.cells,
        "cells_claimed": claimed,
        "cells_taken_from_others": taken,
        "leaderboard_excluded": excluded,
        "review": "awaiting" if needs_review else None,
        "processed_at": res.clock(),
    }
    unset = {} if (needs_review and res.settings.keep_fixes_for_review) else {"fixes": ""}
    await db.runs.update_one({"_id": run_id}, {"$set": update, **({"$unset": unset} if unset else {})})

    if processed.cells:
        await invalidate_leaderboard(res.redis, res.clock())
    await publish_changes(res.redis, changes)
    log.info(
        "run_processed",
        extra={
            "run_id": run_id,
            "status": processed.status,
            "cells": len(processed.cells),
            "claimed": claimed,
            "taken": taken,
            "flags": [f["code"] for f in processed.flags],
        },
    )


async def _claim_cells(res: Resources, run: dict, processed: eng.ProcessedRun) -> tuple[int, int, list[dict]]:
    db, s = res.db, res.settings
    user_id, run_id = run["user_id"], run["_id"]
    cells = processed.cells
    credit = eng.effort_credit(processed.moving_seconds, len(cells))
    delay_ms = s.publish_delay_seconds * 1000

    token = await _acquire(res.redis, s.processing_lock_seconds)
    try:
        now = res.clock()
        powers: dict[str, dict[str, tuple[float, int]]] = {}
        for _attempt in range(2):
            powers = {c: {} for c in cells}
            async for d in db.cell_power.find({"cell": {"$in": cells}}):
                powers[d["cell"]][d["user_id"]] = (d["power"], d["updated_at"])
            involved = {u for p in powers.values() for u in p} | {user_id}
            if not await settle_expired(db, involved, now):
                break
        cell_docs = {d["_id"]: d async for d in db.cells.find({"_id": {"$in": cells}})}
        freezes = await active_freezes(db, {u for p in powers.values() for u in p} | {user_id}, now)

        ops: list[Any] = []
        cell_ops: list[Any] = []
        changes: list[dict] = []
        claimed = taken = 0
        for cell in cells:
            doc = cell_docs.get(cell)
            current = doc["owner_id"] if doc else None
            out = eng.apply_claim(cell, powers[cell], current, user_id, credit, now, freezes)
            p, t = out.powers[user_id]
            ops.append(({"cell": cell, "user_id": user_id}, {"$set": {"power": p, "updated_at": t}}, True))
            final_owner = out.new_owner
            if final_owner == user_id:
                claimed += 1
            if out.changed and final_owner is not None:
                if final_owner == user_id and current is not None:
                    taken += 1
                lat, lng = eng.cell_centre(cell)
                fields = change_fields(doc, final_owner, now, delay_ms, run_id)
                cell_ops.append(({"_id": cell}, {"$set": fields, "$setOnInsert": {"lat": lat, "lng": lng}}, True))
                changes.append({"cell": cell, "new_owner": final_owner, "reveal_at": now + delay_ms})
            elif final_owner == user_id and doc is not None:
                cell_ops.append(({"_id": cell}, {"$set": {"owner_run_id": run_id}}, False))
        for f, u, up in ops:
            await db.cell_power.update_one(f, u, upsert=up)
        for f, u, up in cell_ops:
            await db.cells.update_one(f, u, upsert=up)
    finally:
        await _release(res.redis, token)
    return claimed, taken, changes


async def reassign_after_delete(res: Resources, user_id: str) -> list[dict]:
    """Account deletion: remove the user's power, then give each cell they owned to the strongest remaining
    user (by faded power) or drop the cell. Returns change events for the live channel."""
    db, s = res.db, res.settings
    now = res.clock()
    delay_ms = s.publish_delay_seconds * 1000
    token = await _acquire(res.redis, s.processing_lock_seconds)
    changes: list[dict] = []
    try:
        await db.cell_power.delete_many({"user_id": user_id})
        affected = [
            d
            async for d in db.cells.find(
                {"$or": [{"owner_id": user_id}, {"public_owner_id": user_id}, {"pending_owner_id": user_id}]}
            )
        ]
        ids = [d["_id"] for d in affected]
        powers: dict[str, list[dict]] = {}
        for _attempt in range(2):
            powers = {c: [] for c in ids}
            async for d in db.cell_power.find({"cell": {"$in": ids}}):
                powers[d["cell"]].append(d)
            if not await settle_expired(db, {d["user_id"] for ds in powers.values() for d in ds}, now):
                break
        freezes = await active_freezes(db, {d["user_id"] for ds in powers.values() for d in ds}, now)
        for doc in affected:
            cid = doc["_id"]
            best, best_p = None, -1.0
            for d in powers[cid]:
                fp = eng.faded_power(d["user_id"], d["power"], d["updated_at"], now, freezes.get(d["user_id"]))
                if fp > best_p:
                    best, best_p = d["user_id"], fp
            if best is None:
                await db.cells.delete_one({"_id": cid})
                changes.append({"cell": cid, "new_owner": None, "reveal_at": now})
                continue
            keep = doc["owner_id"] if doc["owner_id"] != user_id else None
            new_owner = keep or best
            await db.cells.update_one(
                {"_id": cid},
                {
                    "$set": {
                        "owner_id": new_owner,
                        "owner_run_id": None,
                        "public_owner_id": None,
                        "pending": True,
                        "pending_owner_id": new_owner,
                        "pending_at": now,
                        "changed_at": now,
                    }
                },
            )
            changes.append({"cell": cid, "new_owner": new_owner, "reveal_at": now + delay_ms})
    finally:
        await _release(res.redis, token)
    await invalidate_leaderboard(res.redis, now)
    return changes
