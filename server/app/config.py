"""Server settings. Every value can be set from the environment (see the aliases)."""

from __future__ import annotations

from functools import lru_cache

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_JWT_SECRET = "insecure-dev-secret-change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="LOOPRUN_", env_file=None, extra="ignore", populate_by_name=True)

    # --- infrastructure ---
    mongo_url: str = Field(
        "mongodb://localhost:27017/looprun", validation_alias=AliasChoices("LOOPRUN_MONGO_URL", "MONGO_URL")
    )
    mongo_db: str = Field("looprun", validation_alias=AliasChoices("LOOPRUN_MONGO_DB"))
    redis_url: str = Field("redis://localhost:6379/0", validation_alias=AliasChoices("LOOPRUN_REDIS_URL", "REDIS_URL"))
    celery_task_always_eager: bool = Field(
        False, validation_alias=AliasChoices("LOOPRUN_CELERY_TASK_ALWAYS_EAGER", "CELERY_TASK_ALWAYS_EAGER")
    )
    log_level: str = Field("INFO", validation_alias=AliasChoices("LOOPRUN_LOG_LEVEL"))

    # --- auth ---
    dev_auth: bool = Field(False, validation_alias=AliasChoices("LOOPRUN_DEV_AUTH"))  # accepts id_token "dev:<name>"
    jwt_secret: str = Field(DEFAULT_JWT_SECRET, validation_alias=AliasChoices("LOOPRUN_JWT_SECRET"))
    jwt_ttl_seconds: int = 30 * 24 * 3600
    jwt_min_secret_length: int = 32  # production (dev auth off) refuses shorter secrets
    google_client_id: str = Field("", validation_alias=AliasChoices("LOOPRUN_GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_ID"))

    # --- uploads ---
    max_fixes: int = Field(20000, ge=1)  # more -> HTTP 413
    max_body_bytes: int = Field(8 * 1024 * 1024, ge=1)  # larger request body (declared or streamed) -> HTTP 413
    run_rate_limit: int = Field(
        30, validation_alias=AliasChoices("LOOPRUN_RUN_RATE_LIMIT")
    )  # uploads per user per window
    run_rate_window_seconds: int = 3600
    # a repeated upload of a run that is still `processing` after this long re-enqueues it (lost message / crash)
    run_reenqueue_after_seconds: float = Field(30.0, ge=0)
    # the sweeper (celery beat, every sweep_interval_seconds) re-enqueues runs `processing` for longer than this
    stuck_run_seconds: float = Field(300.0, ge=0)
    sweep_interval_seconds: float = Field(60.0, gt=0)

    # --- map / privacy ---
    # Delayed publishing: a change of cell owner becomes visible to other people (GET /cells and the
    # WebSocket) only after this many seconds. 0 in tests.
    publish_delay_seconds: int = Field(
        1800, ge=0, validation_alias=AliasChoices("LOOPRUN_PUBLISH_DELAY_SECONDS", "PUBLISH_DELAY_SECONDS")
    )
    # K-anonymity for owner names: a cell shows its owner only when at least K distinct users have power
    # in cells within grid_disk(cell, privacy_radius_k_ring). Otherwise owner=null, hidden=true.
    privacy_min_users: int = Field(3, ge=1, validation_alias=AliasChoices("LOOPRUN_PRIVACY_K", "PRIVACY_MIN_USERS"))
    privacy_ring: int = Field(3, ge=0)  # the "k=3" of grid_disk(k=3)
    cells_rate_limit: int = Field(120, ge=1, validation_alias=AliasChoices("LOOPRUN_CELLS_RATE_LIMIT"))  # per user
    cells_rate_window_seconds: int = Field(60, ge=1)
    bbox_max_degrees: float = 0.2
    cells_max_results: int = 20000
    leaderboard_cache_seconds: int = 60
    leaderboard_size: int = 100

    # --- processing / locks ---
    processing_lock_seconds: int = Field(30, ge=2)  # claims-lock TTL; extended while the holder is alive
    processing_lock_wait_seconds: float = Field(
        60.0, ge=0
    )  # worker waits this long for the lock, then retries the task
    delete_lock_wait_seconds: float = Field(10.0, ge=0)  # DELETE /me waits this long, then answers 503 (safe to retry)

    # --- retention (TTL indexes) ---
    fixes_retention_days: int = Field(30, ge=1)  # raw GPS of runs that are not accepted (accepted: deleted at once)
    reports_retention_days: int = Field(180, ge=1)

    # --- freeze ---
    max_freeze_days: int = Field(30, ge=1, le=30)  # one freeze
    freeze_quota_days: int = Field(30, ge=1)  # at most this many frozen days ...
    freeze_window_days: int = Field(90, ge=1)  # ... in any rolling window of this many days

    # --- websocket ---
    ws_recheck_seconds: float = Field(30.0, gt=0)  # re-check that the user still exists
    ws_max_sockets_per_user: int = Field(5, ge=1)
    ws_auth_timeout_seconds: float = Field(10.0, gt=0)  # first-message auth must arrive within this


@lru_cache
def get_settings() -> Settings:
    return Settings()
