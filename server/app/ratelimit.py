"""Fixed-window Redis counter used by every rate-limited route."""

from __future__ import annotations

from .resources import Resources


async def hit_rate_limit(res: Resources, scope: str, user_id: str, limit: int, window_s: int) -> int | None:
    """Fixed-window counter in Redis. Returns None when allowed, else seconds until the window ends."""
    bucket = (res.clock() // 1000) // window_s
    key = f"looprun:rl:{scope}:{user_id}:{bucket}"
    n = await res.redis.incr(key)
    if n == 1:
        await res.redis.expire(key, window_s)
    if n > limit:
        return max(1, int((bucket + 1) * window_s - res.clock() // 1000))
    return None
