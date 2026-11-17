"""Decay freezes.

The engine only pauses fading while freeze_until is in the future and never forgives paused time later
(engine/NOTES.md #10) and returns *unfaded* power while frozen (engine verifier finding 1). So the server:

* START: rebases the user's cell_power that is already past its grace period to faded(now) with
  updated_at = now - grace, so a freeze can never bring decayed power back;
* END (explicit, replaced by a new freeze, or lazily when it has expired and the user's power is next read):
  moves cell_power.updated_at forward by the time that power spent frozen;
* every cell_power write here is a compare-and-set on (power, updated_at), so it can never overwrite a claim that a
  worker applied meanwhile (settle_expired also runs inside claims, for rows in regions that claim did not lock);
* QUOTA: at most `freeze_quota_days` frozen days in any rolling `freeze_window_days` (default 30 in 90).
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from . import engine_adapter as eng
from .errors import LockLost

DAY_MS = 86_400_000
LOG_KEEP_MS = 400 * DAY_MS


CAS_ATTEMPTS = 8


async def _cas_update(db: Any, row: dict, change: Callable[[dict], dict | None]) -> bool:
    """Compare-and-set a cell_power row: the write only lands when (power, updated_at) are still what `change`
    was computed from. A claim that wrote the row in between wins; we re-read and recompute (or stop when the
    change no longer applies). True if this call changed the row."""
    for _ in range(CAS_ATTEMPTS):
        fields = change(row)
        if fields is None:
            return False
        r = await db.cell_power.update_one(
            {"_id": row["_id"], "power": row["power"], "updated_at": row["updated_at"]}, {"$set": fields}
        )
        if r.matched_count:
            return True
        row = await db.cell_power.find_one({"_id": row["_id"]})
        if row is None:  # deleted meanwhile (account deletion)
            return False
    raise LockLost(f"cell_power row {row['_id']} kept changing")  # RETRYABLE: the caller is retried


async def settle_freeze(db: Any, user: dict, end_ms: int) -> int:
    """Shift the user's power timestamps by the frozen time up to end_ms, log the interval, clear the freeze.
    Returns the number of cell_power rows shifted."""
    started = user.get("freeze_started_at")
    shifted = 0
    log_entry = None
    if started is not None and end_ms > started:
        log_entry = {"start": started, "end": end_ms}
        async for d in db.cell_power.find({"user_id": user["_id"]}):

            def shift(row: dict) -> dict | None:
                if row["updated_at"] >= end_ms:
                    return None  # a claim refreshed it after the freeze: nothing to forgive
                return {"updated_at": row["updated_at"] + end_ms - max(row["updated_at"], started)}

            if await _cas_update(db, d, shift):
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

    def rebase(row: dict) -> dict | None:
        if now - row["updated_at"] <= grace_ms:
            return None  # a claim refreshed the row meanwhile: it keeps its new credit
        p = eng.faded_power(user_id, row["power"], row["updated_at"], now, None)
        return {"power": p, "updated_at": now - grace_ms}

    async for d in db.cell_power.find({"user_id": user_id}):
        if await _cas_update(db, d, rebase):
            n += 1
    return n


def strength(user: dict, row: dict, now: int) -> float:
    """How much of the user's hold on one cell_power row is left at `now`, 0..1.

    faded power / reference power, where the reference is the power right after the last claim (`ref_power`;
    rows written before it existed fall back to the stored power). 1.0 during the grace period after a claim,
    falling towards 0 afterwards. A freeze keeps the value where it was when the freeze began (the freeze start
    rebases `power` to its faded value, the reference stays). A freeze that has run out but is not settled yet
    (settling is lazy) is counted as if it were: the frozen time is forgiven, exactly as settle_freeze will do.
    Read-only.
    """
    power = row["power"]
    if power <= 0:
        return 0.0
    ref = row.get("ref_power") or power
    until, started = user.get("freeze_until"), user.get("freeze_started_at")
    if until is not None and until > now:
        return max(0.0, min(1.0, power / ref))
    updated = row["updated_at"]
    if until is not None and started is not None and until > started and updated < until:
        updated += until - max(updated, started)
    left = eng.faded_power(user["_id"], power, updated, now, None) / ref
    return max(0.0, min(1.0, left))


def used_days(user: dict, now: int, window_days: int) -> int:
    """Whole days (rounded up) the user was frozen inside the last window_days, the running freeze included
    up to now. This is the "x of 30 days used in the last 90 days" figure; it only counts time that has passed."""
    lo = now - window_days * DAY_MS
    intervals = list(user.get("freeze_log", []))
    until, started = user.get("freeze_until"), user.get("freeze_started_at")
    if until is not None and started is not None:
        intervals.append({"start": started, "end": min(now, until)})
    total = sum(_overlap(e["start"], e["end"], lo, now) for e in intervals)
    return -(-total // DAY_MS)
