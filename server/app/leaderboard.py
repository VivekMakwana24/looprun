"""Weekly leaderboard rows (also used for the rank on public profiles)."""

from __future__ import annotations

import json

from .cellview import build_views
from .events import iso_week, leaderboard_key
from .resources import Resources
from .social import display_name


async def public_counts(res: Resources, now: int) -> dict[str, int]:
    """Cells per user counting only what a stranger sees on GET /cells: ownership already published (same delay),
    owner not deleting, and the owner's name not hidden (home zone, K-anonymity). Users whose cells are all hidden
    do not appear at all."""
    counts: dict[str, int] = {}
    batch: list[dict] = []

    async def flush() -> None:
        for v in await build_views(res, batch, None):
            if v["owner"] is not None:
                counts[v["owner"]["id"]] = counts.get(v["owner"]["id"], 0) + 1
        batch.clear()

    async for d in res.db.cells.find({}):
        batch.append(d)
        if len(batch) >= 5000:
            await flush()
    await flush()
    return counts


async def cached_public_counts(res: Resources) -> dict[str, int]:
    s = res.settings
    now = res.clock()
    key = leaderboard_key(iso_week(now))
    if s.leaderboard_cache_seconds > 0:
        cached = await res.redis.get(key)
        if cached:
            return json.loads(cached)
    counts = await public_counts(res, now)
    if s.leaderboard_cache_seconds > 0:
        await res.redis.set(key, json.dumps(counts), ex=s.leaderboard_cache_seconds)
    return counts


async def weekly_rows(res: Resources, viewer_id: str) -> tuple[list[tuple[int, str, str]], int]:
    """The full sorted leaderboard as the viewer sees it: [(cells, name, user_id)], best first, and the viewer's own
    live count. Everybody sees only what the map shows them (published, named); the viewer additionally sees their
    own cells at once, under their real name (others see display_name)."""
    counts = await cached_public_counts(res)
    own = await res.db.cells.count_documents({"owner_id": viewer_id})
    counts = {**counts, viewer_id: own}
    counts = {uid: n for uid, n in counts.items() if n > 0}
    users = {u["_id"]: u async for u in res.db.users.find({"_id": {"$in": sorted(counts)}})}
    rows = sorted(
        (
            (n, users[uid]["name"] if uid == viewer_id else display_name(users[uid]), uid)
            for uid, n in counts.items()
            if uid in users and not users[uid].get("deleting")
        ),
        key=lambda r: (-r[0], r[1], r[2]),
    )
    return rows, own
