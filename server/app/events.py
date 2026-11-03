"""Redis pub/sub for live cell changes, and the leaderboard cache key."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any

CHANNEL = "looprun:cell_changes"


def iso_week(now_ms: int) -> str:
    y, w, _ = datetime.fromtimestamp(now_ms / 1000, UTC).isocalendar()
    return f"{y}-W{w:02d}"


def leaderboard_key(week: str) -> str:
    return f"looprun:leaderboard:{week}"


async def publish_changes(redis: Any, changes: list[dict]) -> None:
    """changes: [{"cell", "new_owner", "reveal_at"}]. Consumers decide per viewer what to show and when."""
    if not changes:
        return
    pipe = redis.pipeline()
    for c in changes:
        pipe.publish(CHANNEL, json.dumps(c))
    await pipe.execute()


async def invalidate_leaderboard(redis: Any, now_ms: int) -> None:
    await redis.delete(leaderboard_key(iso_week(now_ms)))
