"""Decay freezes.

The engine only pauses fading while freeze_until is in the future and does not forgive paused time later
(engine/NOTES.md #10). So when a freeze ends - explicitly (POST /me/freeze days=0), by starting a new one, or
by expiring (settled lazily the next time that user's power is read) - we move the user's cell_power.updated_at
forward by the time that power spent frozen.
"""

from __future__ import annotations

from typing import Any


async def settle_freeze(db: Any, user: dict, end_ms: int) -> int:
    """Shift the user's power timestamps by the frozen time up to end_ms and clear the freeze. Returns docs shifted."""
    started = user.get("freeze_started_at")
    shifted = 0
    if started is not None and end_ms > started:
        ops = []
        async for d in db.cell_power.find({"user_id": user["_id"]}):
            if d["updated_at"] < end_ms:
                ops.append(
                    (
                        {"_id": d["_id"]},
                        {"$set": {"updated_at": d["updated_at"] + end_ms - max(d["updated_at"], started)}},
                    )
                )
        if ops:
            for f, u in ops:
                await db.cell_power.update_one(f, u)
            shifted = len(ops)
    await db.users.update_one({"_id": user["_id"]}, {"$set": {"freeze_until": None, "freeze_started_at": None}})
    return shifted


async def settle_expired(db: Any, user_ids: set[str], now: int) -> bool:
    """Settle every listed user whose freeze has run out. True if anything changed."""
    changed = False
    if not user_ids:
        return False
    async for u in db.users.find({"_id": {"$in": sorted(user_ids)}, "freeze_until": {"$ne": None}}):
        if u["freeze_until"] <= now:
            await settle_freeze(db, u, u["freeze_until"])
            changed = True
    return changed
