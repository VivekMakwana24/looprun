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
    google_client_id: str = Field("", validation_alias=AliasChoices("LOOPRUN_GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_ID"))

    # --- uploads ---
    max_fixes: int = 20000  # more -> HTTP 413
    max_body_bytes: int = 8 * 1024 * 1024  # bigger Content-Length -> HTTP 413
    run_rate_limit: int = Field(
        30, validation_alias=AliasChoices("LOOPRUN_RUN_RATE_LIMIT")
    )  # uploads per user per window
    run_rate_window_seconds: int = 3600
    keep_fixes_for_review: bool = True  # raw GPS is kept only for runs that need a human look; else it is dropped

    # --- map / privacy ---
    # Delayed publishing: a change of cell owner becomes visible to other people (GET /cells and the
    # WebSocket) only after this many seconds. 0 in tests.
    publish_delay_seconds: int = Field(
        1800, validation_alias=AliasChoices("LOOPRUN_PUBLISH_DELAY_SECONDS", "PUBLISH_DELAY_SECONDS")
    )
    # K-anonymity for owner names: a cell shows its owner only when at least K distinct users have power
    # in cells within grid_disk(cell, privacy_radius_k_ring). Otherwise owner=null, hidden=true.
    privacy_min_users: int = Field(3, validation_alias=AliasChoices("LOOPRUN_PRIVACY_K", "PRIVACY_MIN_USERS"))
    privacy_ring: int = 3  # the "k=3" of grid_disk(k=3)
    bbox_max_degrees: float = 0.2
    cells_max_results: int = 20000
    leaderboard_cache_seconds: int = 60
    leaderboard_size: int = 100

    # --- processing ---
    processing_lock_seconds: int = 120


@lru_cache
def get_settings() -> Settings:
    return Settings()
