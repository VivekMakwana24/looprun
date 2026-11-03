"""Run processing (engine -> cells, cell power, ownership) and account deletion.

Everything that changes ownership runs under locks (locks.LockSet: one per user, one per H3 res-5 region).
Processing is idempotent: the claim for a run is first *planned* and stored in `run_claims`
(absolute new values per cell), then applied with guarded absolute writes, so a redelivered task can never
add credit twice.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from pymongo.errors import DuplicateKeyError

from . import engine_adapter as eng
from .cellview import change_fields
from .errors import RETRYABLE, LockTimeout
from .events import publish_changes, publish_user_deleted
from .freeze import settle_expired
from .locks import REGION_RES, LockSet, region_key, user_key
from .resources import Resources

log = logging.getLogger("looprun.processing")

DAY_MS = 86_400_000


def expiry(res: Resources, days: int) -> datetime:
    return datetime.fromtimestamp(res.clock() / 1000, UTC) + timedelta(days=days)


async def active_freezes(db: Any, user_ids: set[str], now: int) -> dict[str, int]:
    out: dict[str, int] = {}
    if not user_ids:
        return out
    async for u in db.users.find({"_id": {"$in": sorted(user_ids)}}, {"freeze_until": 1}):
        fu = u.get("freeze_until")
        if fu and fu > now:
            out[u["_id"]] = fu
    return out


# ------------------------------------------------------------------ run processing
async def process_run_by_id(res: Resources, run_id: str, final: bool = True) -> None:
    """Process one run. Infrastructure errors (RETRYABLE) are re-raised so Celery retries, unless this is the
    final attempt; every other failure marks the run rejected with flag processing_error."""
    run = await res.db.runs.find_one({"_id": run_id})
    if run is None or run.get("status") != "processing":
        return  # unknown, or already processed (task redelivered): nothing to do
    try:
        await _process(res, run)
    except RETRYABLE as e:
        if not final:
            raise
        log.error("processing_gave_up", extra={"run_id": run_id, "error": type(e).__name__})
        await _fail(res, run_id)
    except Exception:  # noqa: BLE001
        log.exception("processing_failed", extra={"run_id": run_id})
        await _fail(res, run_id)


async def _fail(res: Resources, run_id: str) -> None:
    flags = [{"code": "processing_error", "severity": "hard", "detail": "processing failed"}]
    await res.db.runs.update_one(
        {"_id": run_id, "status": "processing"},
        {"$set": {"status": "rejected", "flags": flags, "review": "awaiting", "processed_at": res.clock()}},
    )
    # keep the GPS only until it has been looked at (TTL), not forever
    await res.db.run_fixes.update_one(
        {"_id": run_id}, {"$set": {"expire_at": expiry(res, res.settings.fixes_retention_days)}}
    )


async def _process(res: Resources, run: dict) -> None:
    db, run_id, user_id = res.db, run["_id"], run["user_id"]
    user = await db.users.find_one({"_id": user_id})
    if user is None or user.get("deleting"):
        return  # the account is going away: claim nothing (DELETE /me removes the run)
    fx = await db.run_fixes.find_one({"_id": run_id})
    if fx is None:
        raise ValueError("run has no stored fixes")
    processed = eng.process_run(fx["fixes"])

    claimed = taken = 0
    changes: list[dict] = []
    credit = eng.effort_credit(processed.moving_seconds, len(processed.cells)) if processed.cells else 0.0
    if processed.cells and credit > 0:  # zero credit would only refresh the grace period for free
        claim = await _claim_cells(res, run, processed, credit)
        if claim is not None:
            claimed, taken, changes = claim["claimed"], claim["taken"], claim["changes"]
            if claim["skipped"]:
                return

    status = processed.status
    update: dict[str, Any] = {
        "status": status,
        "distance_m": processed.distance_m,
        "moving_seconds": processed.moving_seconds,
        "loops": processed.loops,
        "flags": processed.flags,
        "cells": processed.cells,
        "cells_claimed": claimed,
        "cells_taken_from_others": taken,
        "review": "awaiting" if status != "accepted" else None,
        "processed_at": res.clock(),
    }
    await db.runs.update_one({"_id": run_id}, {"$set": update})
    if status == "accepted":
        await db.run_fixes.delete_one({"_id": run_id})  # clean runs: raw GPS goes at once
    else:
        await db.run_fixes.update_one(
            {"_id": run_id}, {"$set": {"expire_at": expiry(res, res.settings.fixes_retention_days)}}
        )
    await publish_changes(res.redis, changes)
    log.info(
        "run_processed",
        extra={
            "run_id": run_id,
            "status": status,
            "cells": len(processed.cells),
            "claimed": claimed,
            "taken": taken,
            "flags": [f["code"] for f in processed.flags],
        },
    )


async def _claim_cells(res: Resources, run: dict, processed: eng.ProcessedRun, credit: float) -> dict | None:
    s = res.settings
    # Lock order: the user's lock first (serialises with that user's account deletion), then one lock per H3
    # resolution-5 region of the claimed cells, sorted. Runs in different regions do not wait for each other.
    regions = sorted({eng.region_of(c, REGION_RES) for c in processed.cells})
    keys = [user_key(run["user_id"]), *(region_key(r) for r in regions)]
    async with LockSet(res.redis, keys, ttl_s=s.processing_lock_seconds, wait_s=s.processing_lock_wait_seconds) as lock:
        user = await res.db.users.find_one({"_id": run["user_id"]})
        if user is None or user.get("deleting"):  # re-checked inside the lock: DELETE /me may have started
            return {"skipped": True, "claimed": 0, "taken": 0, "changes": []}
        plan = await res.db.run_claims.find_one({"_id": run["_id"]})
        if plan is None:
            plan = await _plan(res, run, processed, credit)
        if not plan["applied"]:
            for o in plan["outcomes"]:
                lock.check()
                await _apply(res.db, plan["user_id"], o)
            await res.db.run_claims.update_one({"_id": run["_id"]}, {"$set": {"applied": True}})
        changes = [
            {"cell": o["cell"], "new_owner": o["owner"], "reveal_at": o["reveal_at"]}
            for o in plan["outcomes"]
            if o["changed"]
        ]
        return {"skipped": False, "claimed": plan["claimed"], "taken": plan["taken"], "changes": changes}


async def _plan(res: Resources, run: dict, processed: eng.ProcessedRun, credit: float) -> dict:
    """Decide the outcome for every cell and store it (absolute values) before anything is written."""
    db, s = res.db, res.settings
    user_id, cells = run["user_id"], processed.cells
    delay_ms = s.publish_delay_seconds * 1000
    now = res.clock()
    powers: dict[str, dict[str, tuple[float, int]]] = {}
    for _attempt in range(2):
        powers = {c: {} for c in cells}
        async for d in db.cell_power.find({"cell": {"$in": cells}}):
            powers[d["cell"]][d["user_id"]] = (d["power"], d["updated_at"])
        if not await settle_expired(db, {u for p in powers.values() for u in p} | {user_id}, now):
            break
    cell_docs = {d["_id"]: d async for d in db.cells.find({"_id": {"$in": cells}})}
    freezes = await active_freezes(db, {u for p in powers.values() for u in p} | {user_id}, now)

    outcomes: list[dict] = []
    claimed = taken = 0
    for cell in cells:
        doc = cell_docs.get(cell)
        current = doc["owner_id"] if doc else None
        out = eng.apply_claim(cell, powers[cell], current, user_id, credit, now, freezes)
        p, t = out.powers[user_id]
        lat, lng = eng.cell_centre(cell)
        changed = out.changed and out.new_owner is not None
        if out.new_owner == user_id:
            claimed += 1
            if changed and current is not None:
                taken += 1
        outcomes.append(
            {
                "cell": cell,
                "p": p,
                "t": t,
                "lat": lat,
                "lng": lng,
                "owner": out.new_owner,
                "changed": changed,
                "reveal_at": now + delay_ms,
                "fields": change_fields(doc, out.new_owner, now, delay_ms) if changed else None,
            }
        )
    plan = {
        "_id": run["_id"],
        "user_id": user_id,
        "applied": False,
        "claimed": claimed,
        "taken": taken,
        "outcomes": outcomes,
        "created_at": now,
    }
    try:
        await db.run_claims.insert_one(plan)
    except DuplicateKeyError:  # another attempt planned first: use its plan
        plan = await db.run_claims.find_one({"_id": run["_id"]})
    return plan


async def _apply(db: Any, user_id: str, o: dict) -> None:
    """Idempotent, guarded absolute writes: an older plan never overwrites newer data."""
    cell = o["cell"]
    r = await db.cell_power.update_one(
        {"cell": cell, "user_id": user_id, "updated_at": {"$lte": o["t"]}},
        {"$set": {"power": o["p"], "updated_at": o["t"]}},
    )
    if r.matched_count == 0:
        try:
            await db.cell_power.insert_one({"cell": cell, "user_id": user_id, "power": o["p"], "updated_at": o["t"]})
        except DuplicateKeyError:
            pass  # a newer row exists
    if o["changed"]:
        fields = o["fields"]
        r = await db.cells.update_one({"_id": cell, "changed_at": {"$lte": fields["changed_at"]}}, {"$set": fields})
        if r.matched_count == 0:
            try:
                await db.cells.insert_one({"_id": cell, "lat": o["lat"], "lng": o["lng"], **fields})
            except DuplicateKeyError:
                pass


# ------------------------------------------------------------------ account deletion
DELETE_ATTEMPTS = 5


async def _user_regions(db: Any, user_id: str) -> list[str]:
    """Regions holding anything of this user: power rows, and cells they own or show (a half-finished earlier
    attempt may already have deleted the power rows while cells still point at the user)."""
    cells: set[str] = set()
    async for d in db.cell_power.find({"user_id": user_id}, {"cell": 1}):
        cells.add(d["cell"])
    q = {"$or": [{"owner_id": user_id}, {"public_owner_id": user_id}, {"pending_owner_id": user_id}]}
    async for d in db.cells.find(q, {"_id": 1}):
        cells.add(d["_id"])
    return sorted({eng.region_of(c, REGION_RES) for c in cells})


async def delete_account(res: Resources, user_id: str) -> None:
    """Resumable account deletion.

    1. mark the user `deleting`: no new uploads, and workers skip claiming for them (re-checked inside the lock);
    2. take the user's lock (waits for a claim in flight), then the region locks of everything they hold
       (bounded wait, a few attempts); hand over / clear their cells and delete their cell_power;
    3. delete runs, raw fixes, claim plans and the reports they filed;
    4. delete the user document LAST.
    Any failure leaves the user in `deleting`; the token still works for DELETE /me, so calling it again finishes.
    """
    db, s = res.db, res.settings
    await db.users.update_one({"_id": user_id}, {"$set": {"deleting": True}})
    await publish_user_deleted(res.redis, user_id)  # open WebSockets of this user close now
    changes: list[dict] = []
    ukey = user_key(user_id)
    async with LockSet(
        res.redis, [ukey], ttl_s=s.processing_lock_seconds, wait_s=s.delete_lock_wait_seconds
    ) as user_lock:
        # With the user lock held no claim of theirs is in flight and none can start (they see `deleting`),
        # so the regions found below are stable. Their locks are taken on top, in sorted order.
        for attempt in range(DELETE_ATTEMPTS):
            keys = [region_key(r) for r in await _user_regions(db, user_id)]
            try:
                async with LockSet(
                    res.redis, keys, ttl_s=s.processing_lock_seconds, wait_s=s.delete_lock_wait_seconds
                ) as region_locks:

                    def still_held(a=user_lock, b=region_locks) -> None:
                        a.check()
                        b.check()

                    changes = await _reassign_cells(res, user_id, still_held)
                break
            except LockTimeout:
                if attempt == DELETE_ATTEMPTS - 1:
                    raise
    await db.run_fixes.delete_many({"user_id": user_id})
    await db.run_claims.delete_many({"user_id": user_id})
    await db.runs.delete_many({"user_id": user_id})
    await db.reports.delete_many({"reporter_id": user_id})
    await db.users.delete_one({"_id": user_id})
    await publish_changes(res.redis, changes)
    await publish_user_deleted(res.redis, user_id)
    log.info("account_deleted", extra={"cells_reassigned": len(changes)})


async def _reassign_cells(res: Resources, user_id: str, check: Callable[[], None]) -> list[dict]:
    """Give each cell the user owned (or showed) to the strongest remaining user by faded power, else drop it."""
    db = res.db
    now = res.clock()
    delay_ms = res.settings.publish_delay_seconds * 1000
    changes: list[dict] = []
    await db.cell_power.delete_many({"user_id": user_id})
    q = {"$or": [{"owner_id": user_id}, {"public_owner_id": user_id}, {"pending_owner_id": user_id}]}
    affected = [d async for d in db.cells.find(q)]
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
        check()
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
        new_owner = doc["owner_id"] if doc["owner_id"] != user_id else best
        await db.cells.update_one(
            {"_id": cid},
            {
                "$set": {
                    "owner_id": new_owner,
                    "public_owner_id": None,
                    "pending": True,
                    "pending_owner_id": new_owner,
                    "pending_at": now,
                    "changed_at": now,
                }
            },
        )
        changes.append({"cell": cid, "new_owner": new_owner, "reveal_at": now + delay_ms})
    return changes
