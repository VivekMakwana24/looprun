"""Celery app and the run-processing task.

Worker:  celery -A app.worker:celery_app worker --loglevel=info
Tests:   configure_celery(settings) with celery_task_always_eager=True runs tasks inline.
"""

from __future__ import annotations

import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any

from celery import Celery

from .config import Settings, get_settings
from .errors import RETRYABLE
from .logging_config import setup_logging
from .resources import make_resources

log = logging.getLogger("looprun.worker")

_settings: Settings | None = None

celery_app = Celery("looprun")


def configure_celery(settings: Settings) -> None:
    global _settings
    _settings = settings
    celery_app.conf.update(
        broker_url=settings.redis_url,
        result_backend=None,
        task_ignore_result=True,
        task_always_eager=settings.celery_task_always_eager,
        task_eager_propagates=True,
        task_acks_late=True,
        worker_prefetch_multiplier=1,
        task_serializer="json",
        accept_content=["json"],
        broker_connection_retry_on_startup=True,
        # run `celery -A app.worker:celery_app beat` (or worker -B) for the sweeper; see server/NOTES.md
        beat_schedule={
            "sweep-stuck-runs": {"task": "looprun.sweep_stuck_runs", "schedule": settings.sweep_interval_seconds}
        },
    )


def _current_settings() -> Settings:
    return _settings or get_settings()


configure_celery(get_settings())


def run_sync(coro: Any) -> Any:
    """Run a coroutine to completion from sync code, even if this thread already runs an event loop."""
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return asyncio.run(coro)
    with ThreadPoolExecutor(max_workers=1) as ex:
        return ex.submit(asyncio.run, coro).result()


async def _process(run_id: str, final: bool) -> None:
    from .processing import process_run_by_id  # noqa: PLC0415

    res = make_resources(_current_settings())
    try:
        await process_run_by_id(res, run_id, final=final)
    finally:
        await res.close()


@celery_app.task(
    name="looprun.process_run",
    bind=True,
    autoretry_for=RETRYABLE,
    retry_backoff=True,
    retry_backoff_max=300,
    retry_jitter=True,
    max_retries=6,
)
def process_run(self: Any, run_id: str) -> None:
    """Retries Mongo/Redis connection trouble with backoff; on the last attempt the run is marked rejected
    (processing_error) instead of staying `processing` forever."""
    setup_logging(_current_settings().log_level)
    run_sync(_process(run_id, final=self.request.retries >= self.max_retries))


def enqueue_run(run_id: str) -> None:
    """Put a run on the queue. Only the id travels through Redis; the fixes stay in Mongo."""
    process_run.delay(run_id)


async def _sweep() -> int:
    from .processing import sweep_stuck_runs  # noqa: PLC0415

    res = make_resources(_current_settings())
    try:
        return await sweep_stuck_runs(res, enqueue_run)
    finally:
        await res.close()


@celery_app.task(name="looprun.sweep_stuck_runs")
def sweep_stuck_runs_task() -> int:
    """Periodic (celery beat): re-enqueue runs stuck in `processing` for more than settings.stuck_run_seconds."""
    setup_logging(_current_settings().log_level)
    return run_sync(_sweep())
