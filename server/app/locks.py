"""A Redis lock that is safe to share between workers.

* every holder has its own random token;
* release is an atomic compare-and-delete (Lua), so a late worker can never free another worker's lock;
* the TTL is short (a dead worker blocks others for at most one TTL); a watchdog extends it while the holder lives;
* if the lock is lost anyway, `check()` raises LockLost so the holder stops writing (the claim step is idempotent).
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

CLAIMS_KEY = "looprun:lock:claims"


class RedisLock:
    def __init__(
        self, redis: Any, key: str = CLAIMS_KEY, ttl_s: int = 30, wait_s: float = 60.0, auto_extend: bool = True
    ):
        self.redis, self.key, self.ttl_s, self.wait_s, self.auto_extend = redis, key, ttl_s, wait_s, auto_extend
        self.token = uuid.uuid4().hex
        self.lost = False
        self._task: asyncio.Task | None = None

    async def acquire(self) -> None:
        waited = 0.0
        while not await self.redis.set(self.key, self.token, nx=True, ex=self.ttl_s):
            if waited >= self.wait_s:
                raise LockTimeout(f"could not acquire {self.key} within {self.wait_s}s")
            await asyncio.sleep(0.05)
            waited += 0.05
        if self.auto_extend:
            self._task = asyncio.create_task(self._watchdog())

    async def _watchdog(self) -> None:
        while True:
            await asyncio.sleep(self.ttl_s / 3)
            try:
                if not await self.redis.eval(_EXTEND, 1, self.key, self.token, self.ttl_s):
                    self.lost = True
                    log.error("claims lock lost")
                    return
            except Exception:  # noqa: BLE001 - keep trying; the TTL gives us a margin
                log.warning("lock extension failed", exc_info=True)

    def check(self) -> None:
        if self.lost:
            raise LockLost("claims lock was lost")

    async def release(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._task
            self._task = None
        with contextlib.suppress(Exception):
            await self.redis.eval(_RELEASE, 1, self.key, self.token)

    async def __aenter__(self) -> RedisLock:
        await self.acquire()
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.release()
