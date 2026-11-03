"""Error classes that mean 'infrastructure hiccup, try again' (Celery retries these with backoff)."""

from __future__ import annotations

from pymongo.errors import AutoReconnect, ConnectionFailure
from redis.exceptions import ConnectionError as RedisConnectionError
from redis.exceptions import TimeoutError as RedisTimeoutError


class LockTimeout(TimeoutError):
    """Could not get the claims lock within the allowed wait."""


class LockLost(RuntimeError):
    """The claims lock expired or was taken over while we still held it; the work must be redone."""


# AutoReconnect covers ServerSelectionTimeoutError and NetworkTimeout. OSError covers socket errors and TimeoutError.
RETRYABLE: tuple[type[BaseException], ...] = (
    OSError,
    TimeoutError,
    AutoReconnect,
    ConnectionFailure,
    RedisConnectionError,
    RedisTimeoutError,
    LockLost,
)
