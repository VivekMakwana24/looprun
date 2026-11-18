"""Notification rows (docs/PHASE1_SPEC.md 7). Creation helpers live here; the inbox routes are in social_api.py."""

from __future__ import annotations

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
