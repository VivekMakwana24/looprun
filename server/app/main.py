"""FastAPI application factory.  uvicorn app.main:create_app --factory"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from . import api, live
from . import engine_adapter as eng
from .auth import GoogleVerifier, google_verify
from .bodylimit import BodyLimitMiddleware
from .config import DEFAULT_JWT_SECRET, Settings, get_settings
from .logging_config import setup_logging
from .resources import Resources, ensure_indexes, make_resources
from .worker import configure_celery

log = logging.getLogger("looprun.main")


def create_app(
    settings: Settings | None = None,
    google_verifier: GoogleVerifier | None = None,
    resources: Resources | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    setup_logging(settings.log_level)
    eng.validate_config()
    if not settings.dev_auth and (
        settings.jwt_secret == DEFAULT_JWT_SECRET or len(settings.jwt_secret) < settings.jwt_min_secret_length
    ):
        raise RuntimeError(f"LOOPRUN_JWT_SECRET must be set to at least {settings.jwt_min_secret_length} characters")
    if settings.jwt_secret == DEFAULT_JWT_SECRET:
        log.warning("using the default JWT secret; fine for development only")
    if settings.dev_auth and settings.google_client_id:
        log.warning("LOOPRUN_DEV_AUTH is on although a Google client id is set: never run this in production")
    configure_celery(settings)
    res = resources or make_resources(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await ensure_indexes(res.db)
        yield
        await res.close()

    app = FastAPI(title="Looprun API", version="1.0.0", lifespan=lifespan)
    app.state.res = res
    app.state.google_verifier = google_verifier or google_verify

    app.add_middleware(BodyLimitMiddleware, max_bytes=settings.max_body_bytes)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        # Never echo the rejected input: it can be NaN/Infinity, which JSON cannot carry (that was a 500).
        detail = [{"loc": [str(x) for x in e["loc"]], "msg": e["msg"], "type": e["type"]} for e in exc.errors()]
        return JSONResponse({"detail": detail}, status_code=422)

    @app.get("/healthz")
    @app.get("/v1/healthz")
    async def healthz() -> JSONResponse:
        problems = []
        try:
            await res.redis.ping()
        except Exception:  # noqa: BLE001
            problems.append("redis")
        try:
            await res.db.command("ping")
        except Exception:  # noqa: BLE001
            problems.append("mongo")
        if problems:
            return JSONResponse({"status": "degraded", "down": problems}, status_code=503)
        return JSONResponse({"status": "ok"})

    app.include_router(api.router)
    app.include_router(live.router)
    return app
