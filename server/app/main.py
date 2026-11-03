"""FastAPI application factory.  uvicorn app.main:create_app --factory"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from . import api, live
from .auth import GoogleVerifier, google_verify
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
    if settings.jwt_secret == DEFAULT_JWT_SECRET:
        if not settings.dev_auth:
            raise RuntimeError("LOOPRUN_JWT_SECRET must be set (dev auth is off)")
        log.warning("using the default JWT secret; fine for development only")
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

    @app.middleware("http")
    async def limit_body(request: Request, call_next):
        cl = request.headers.get("content-length")
        if cl and cl.isdigit() and int(cl) > settings.max_body_bytes:
            return JSONResponse({"detail": "Payload too large"}, status_code=413)
        return await call_next(request)

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
