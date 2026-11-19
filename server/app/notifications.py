"""Notification rows (docs/PHASE1_SPEC.md 7). Creation helpers live here; the inbox routes are in social_api.py."""

from __future__ import annotations

import hashlib
import hmac
from datetime import UTC, datetime, timedelta
from typing import Any

from .resources import Resources


async def notify(
    res: Resources, nid: str, user_id: str, ntype: str, actor_id: str | None, visible_at: int, **extra: Any
) -> bool:
    """Idempotent by `nid`: the row is written once and never changed afterwards (so `read` is never reset by a
    redelivery). Returns True when this call created it. Nothing is delivered before `visible_at`."""
    now = res.clock()
    doc = {
        "user_id": user_id,
        "type": ntype,
        "actor_id": actor_id,
        "run_id": None,
        "comment_id": None,
        "comment_preview": None,
        "created_at": now,
        "visible_at": visible_at,
        "read": False,
        "expire_at": datetime.fromtimestamp(now / 1000, UTC) + timedelta(days=res.settings.notification_retention_days),
        **extra,
    }
    r = await res.db.notifications.update_one({"_id": nid}, {"$setOnInsert": doc}, upsert=True)
    return r.upserted_id is not None


def cells_taken_id(res: Resources, run_id: str, victim_id: str) -> str:
    """Deterministic id of the 'cells taken' notification of one run for one victim. The id is sent to the victim,
    who can read run ids of the runners they follow, so it is an HMAC keyed with a server secret
    (`notification_id_secret`, else the JWT secret): nobody can derive it from, or link it to, a run id."""
    s = res.settings
    key = (s.notification_id_secret or s.jwt_secret).encode()
    mac = hmac.new(key, f"cells_taken\0{run_id}\0{victim_id}".encode(), hashlib.sha256).hexdigest()[:32]
    return f"cells_taken:{mac}"


async def notify_cells_taken(res: Resources, run_id: str, taker_id: str) -> int:
    """One `cells_taken` notification per victim of this run (however many cells), visible when the first of the
    run's events becomes visible. Idempotent: called from inside the claim lock on every delivery of the run, it
    never duplicates a row or resets `read`. Returns how many victims the run has."""
    delay = res.settings.publish_delay_seconds * 1000
    first_at: dict[str, int] = {}
    async for ev in res.db.battle_events.find({"run_id": run_id, "taker_id": taker_id}, {"victim_id": 1, "at": 1}):
        if ev.get("victim_id"):
            first_at[ev["victim_id"]] = min(ev["at"], first_at.get(ev["victim_id"], ev["at"]))
    for victim, at in first_at.items():
        await notify(
            res, cells_taken_id(res, run_id, victim), victim, "cells_taken", taker_id, at + delay, run_id=run_id
        )
    return len(first_at)
