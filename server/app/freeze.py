"""Decay freezes.

The engine only pauses fading while freeze_until is in the future and never forgives paused time later
(engine/NOTES.md #10) and returns *unfaded* power while frozen (engine verifier finding 1). So the server:

* START: rebases the user's cell_power that is already past its grace period to faded(now) with
  updated_at = now - grace, so a freeze can never bring decayed power back;
* END (explicit, replaced by a new freeze, or lazily when it has expired and the user's power is next read):
  moves cell_power.updated_at forward by the time that power spent frozen;
* QUOTA: at most `freeze_quota_days` frozen days in any rolling `freeze_window_days` (default 30 in 90).
"""

from __future__ import annotations

from typing import Any

from . import engine_adapter as eng

DAY_MS = 86_400_000
LOG_KEEP_MS = 400 * DAY_MS


async def settle_freeze(db: Any, user: dict, end_ms: int) -> int:
    """Shift the user's power timestamps by the frozen time up to end_ms, log the interval, clear the freeze.
    Returns the number of cell_power rows shifted."""
    started = user.get("freeze_started_at")
    shifted = 0
    log_entry = None
    if started is not None and end_ms > started:
        log_entry = {"start": started, "end": end_ms}
        async for d in db.cell_power.find({"user_id": user["_id"]}):
            if d["updated_at"] < end_ms:
                new = d["updated_at"] + end_ms - max(d["updated_at"], started)
                await db.cell_power.update_one({"_id": d["_id"]}, {"$set": {"updated_at": new}})
                shifted += 1
    log = [e for e in user.get("freeze_log", []) if e["end"] > end_ms - LOG_KEEP_MS]
    if log_entry:
        log.append(log_entry)
    await db.users.update_one(
        {"_id": user["_id"]}, {"$set": {"freeze_until": None, "freeze_started_at": None, "freeze_log": log}}
    )
    user.update(freeze_until=None, freeze_started_at=None, freeze_log=log)
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


def _overlap(a0: int, a1: int, b0: int, b1: int) -> int:
    return max(0, min(a1, b1) - max(a0, b0))


def quota_ok(intervals: list[dict], now: int, days: int, quota_days: int, window_days: int) -> bool:
    """Would a freeze [now, now+days] keep every rolling window of window_days at <= quota_days frozen?
    The frozen total in a window ending at e is piecewise linear in e, so its maximum is at now, at the end
    of the new freeze, or where an old interval starts to leave the window."""
    w, quota = window_days * DAY_MS, quota_days * DAY_MS
    new_end = now + days * DAY_MS
    candidates = {now, new_end} | {e["start"] + w for e in intervals if now < e["start"] + w < new_end}
    for end in candidates:
        total = sum(_overlap(e["start"], e["end"], end - w, end) for e in intervals)
        total += _overlap(now, new_end, end - w, end)
        if total > quota:
            return False
    return True


async def rebase_for_freeze(db: Any, user_id: str, now: int) -> int:
    """power := faded(now), updated_at := now - grace for rows that are already past their grace period."""
    grace_ms = int(eng.grace_days() * DAY_MS)
    n = 0
    async for d in db.cell_power.find({"user_id": user_id}):
        if now - d["updated_at"] > grace_ms:
            p = eng.faded_power(user_id, d["power"], d["updated_at"], now, None)
            await db.cell_power.update_one({"_id": d["_id"]}, {"$set": {"power": p, "updated_at": now - grace_ms}})
            n += 1
    return n
