"""Redis locks that are safe to share between workers.

* every lock has its own random holder token;
* release and extension are atomic compare-and-act Lua scripts, so a late worker can never free or extend a lock
  that another worker now holds;
* the TTL is short (a dead worker blocks others for at most one TTL); a watchdog extends it while the holder lives;
* if a lock is lost anyway, `check()` raises LockLost so the holder stops writing (the claim step is idempotent);
* `LockSet` takes several locks in the order given. Callers pass keys in one global order (user lock first, then
  region locks sorted), so two holders can never wait for each other (no deadlock).

Lock keys: one per user (serialises a user's claims against that user's account deletion) and one per H3
resolution-5 region (serialises claims that touch the same area; claims in different regions run in parallel).
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
import uuid
from typing import Any

from .errors import LockLost, LockTimeout

log = logging.getLogger("looprun.locks")

_RELEASE = "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end"
_EXTEND = (
    "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('expire', KEYS[1], ARGV[2]) else return 0 end"
)

REGION_RES = 5
KEY_PREFIX = "looprun:lock:"


def region_key(region: str) -> str:
    return f"{KEY_PREFIX}region:{region}"


def user_key(user_id: str) -> str:
    return f"{KEY_PREFIX}user:{user_id}"


class RedisLock:
    """One lock key with its own holder token. No watchdog: LockSet owns that."""

    def __init__(self, redis: Any, key: str, ttl_s: int):
        self.redis, self.key, self.ttl_s = redis, key, ttl_s
        self.token = uuid.uuid4().hex

    async def try_acquire(self) -> bool:
        return bool(await self.redis.set(self.key, self.token, nx=True, ex=self.ttl_s))

    async def extend(self) -> bool:
        return bool(await self.redis.eval(_EXTEND, 1, self.key, self.token, self.ttl_s))

    async def release(self) -> bool:
        return bool(await self.redis.eval(_RELEASE, 1, self.key, self.token))


class LockSet:
    def __init__(self, redis: Any, keys: list[str], ttl_s: int = 30, wait_s: float = 60.0, poll_s: float = 0.02):
        self.locks = [RedisLock(redis, k, ttl_s) for k in keys]
        self.ttl_s, self.wait_s, self.poll_s = ttl_s, wait_s, poll_s
        self.lost = False
        self._held: list[RedisLock] = []
        self._task: asyncio.Task | None = None

    async def acquire(self) -> None:
        """Take every lock in order. The wait budget covers the whole set; on failure nothing stays held.
        The watchdog starts with the first lock, so a lock taken early cannot expire while we wait for a later
        one; if any lock is lost meanwhile the whole set fails with LockLost and releases what it holds."""
        loop = asyncio.get_running_loop()
        deadline = loop.time() + self.wait_s
        try:
            for lock in self.locks:
                while not await lock.try_acquire():
                    self.check()
                    if loop.time() >= deadline:
                        raise LockTimeout(f"could not acquire {lock.key} within {self.wait_s}s")
                    await asyncio.sleep(self.poll_s)
                self._held.append(lock)
                if self._task is None:
                    self._task = asyncio.create_task(self._watchdog())
                self.check()
            self.check()
        except BaseException:
            await self.release()
            raise

    async def _watchdog(self) -> None:
        while True:
            await asyncio.sleep(self.ttl_s / 3)
            for lock in list(self._held):
                try:
                    if not await lock.extend():
                        self.lost = True
                        log.error("lock lost", extra={"lock": lock.key})
                        # the whole set is void: free the others at once (release() is idempotent)
                        await self._release_all()
                        return
                except Exception:  # noqa: BLE001 - keep trying; the TTL gives us a margin
                    log.warning("lock extension failed", exc_info=True)

    def check(self) -> None:
        if self.lost:
            raise LockLost("a lock was lost while held")

    async def _release_all(self) -> None:
        for lock in reversed(self._held):
            with contextlib.suppress(Exception):
                await lock.release()
        self._held = []

    async def release(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._task
            self._task = None
        await self._release_all()

    async def __aenter__(self) -> LockSet:
        await self.acquire()
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.release()
