from __future__ import annotations

import asyncio
import dataclasses
import math
import os
import types
import uuid

import pytest
from fakeredis import FakeAsyncRedis, FakeServer
from fastapi.testclient import TestClient
from mongomock_motor import AsyncMongoMockClient

from app import engine_adapter
from app.config import Settings
from app.main import create_app
from app.resources import Resources, set_resource_factory

from . import fake_engine

T0 = 1_800_000_000_000  # an arbitrary "now" in epoch ms
DAY = 86_400_000


def _pick_engine():
    want = os.environ.get("LOOPRUN_TEST_ENGINE", "auto")
    if want != "fake":
        try:
            import looprun_engine

            if hasattr(looprun_engine, "process_run") and hasattr(looprun_engine, "apply_claim"):
                return "real", looprun_engine
        except ImportError:
            if want == "real":
                raise
    return "fake", fake_engine


ENGINE_NAME, ENGINE = _pick_engine()


def pytest_report_header(config):
    return f"looprun engine used by server tests: {ENGINE_NAME}"


class Clock:
    def __init__(self, now: int = T0):
        self.now = now

    def __call__(self) -> int:
        return self.now

    def advance(self, ms: int = 0, *, days: float = 0, seconds: float = 0) -> None:
        self.now += int(ms + days * DAY + seconds * 1000)


@pytest.fixture(autouse=True)
def _engine():
    engine_adapter.set_engine(ENGINE)
    yield
    engine_adapter.set_engine(None)
    set_resource_factory(None)


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def make_app(clock):
    """make_app(**settings_overrides, google_verifier=None) -> TestClient (entered). Mongo/Redis are fakes."""
    stack: list[TestClient] = []

    def _make(google_verifier=None, **overrides):
        base = dict(
            dev_auth=True,
            jwt_secret="test-secret-test-secret-test-secret-32b",
            publish_delay_seconds=0,
            celery_task_always_eager=True,
            run_rate_limit=1000,
            leaderboard_cache_seconds=0,
        )
        base.update(overrides)
        settings = Settings(**base)
        server = FakeServer()
        mongo = AsyncMongoMockClient()

        def factory(s: Settings) -> Resources:
            return Resources(s, mongo["looprun"], FakeAsyncRedis(server=server, decode_responses=True), clock)

        set_resource_factory(factory)
        client = TestClient(create_app(settings, google_verifier=google_verifier))
        client.__enter__()
        stack.append(client)
        return client

    yield _make
    for c in reversed(stack):
        c.__exit__(None, None, None)


@pytest.fixture
def client(make_app):
    return make_app()


# ---------------------------------------------------------------- helpers
def login(client: TestClient, name: str) -> dict:
    r = client.post("/v1/auth/google", json={"id_token": f"dev:{name}"})
    assert r.status_code == 200, r.text
    body = r.json()
    return {"Authorization": f"Bearer {body['access_token']}", "_uid": body["user"]["id"]}


def hdr(h: dict) -> dict:
    return {"Authorization": h["Authorization"]}


def square_fixes(lat=50.0, lng=8.7, side_m=400.0, speed=3.0, t0=T0, step_s=5, mock_every=0):
    """A closed square run (ends exactly at the start), one fix per step_s seconds."""
    dlat = side_m / 111_320.0
    dlng = side_m / (111_320.0 * math.cos(math.radians(lat)))
    corners = [(lat, lng), (lat + dlat, lng), (lat + dlat, lng + dlng), (lat, lng + dlng), (lat, lng)]
    pts = []
    step = speed * step_s
    for (a, b), (c, d) in zip(corners, corners[1:], strict=False):
        seg = math.hypot((c - a) * 111_320.0, (d - b) * 111_320.0 * math.cos(math.radians(lat)))
        n = max(1, round(seg / step))
        for i in range(n):
            pts.append((a + (c - a) * i / n, b + (d - b) * i / n))
    pts.append(corners[-1])
    return [
        {
            "lat": p[0],
            "lng": p[1],
            "t": t0 + i * step_s * 1000,
            "acc": 5.0,
            "mock": bool(mock_every and i % mock_every == 0),
        }
        for i, p in enumerate(pts)
    ]


def upload(client, h, fixes, run_id=None, expect=202):
    rid = run_id or str(uuid.uuid4())
    body = {"id": rid, "started_at": fixes[0]["t"], "ended_at": fixes[-1]["t"], "fixes": fixes}
    r = client.post("/v1/runs", json=body, headers=hdr(h))
    assert r.status_code == expect, r.text
    return rid, r


def run_loop(client, h, **kw):
    """Upload a square loop and return the finished RunStatus json."""
    rid, _ = upload(client, h, square_fixes(**kw))
    r = client.get(f"/v1/runs/{rid}", headers=hdr(h))
    assert r.status_code == 200
    return r.json()


def cells_of(client, h, bbox="8.6,49.9,8.8,50.1"):
    r = client.get("/v1/cells", params={"bbox": bbox}, headers=hdr(h))
    assert r.status_code == 200, r.text
    return r.json()["cells"]


def db_run(client, coro_fn):
    """Run an async db helper against the app's fake Mongo: db_run(client, lambda db: db.runs.count_documents({}))."""
    return asyncio.run(coro_fn(client.app.state.res.db))


def with_flag(code: str, severity: str, when):
    """Wrap the active engine so process_run(fixes) adds a flag whenever when(fixes) is true."""
    inner = ENGINE

    class Wrapped:
        def __getattr__(self, name):
            return getattr(inner, name)

        def process_run(self, fixes, *a, **k):
            r = inner.process_run(fixes, *a, **k)
            if not when(fixes):
                return r
            return types.SimpleNamespace(
                distance_m=r.distance_m,
                moving_seconds=r.moving_seconds,
                loops=r.loops,
                cells=r.cells,
                flags=[*r.flags, inner.Flag(code=code, severity=severity, detail="test")],
            )

    engine_adapter.set_engine(Wrapped())


def with_result(when, **changes):
    """Wrap the active engine so that process_run(fixes) returns the real result with some fields replaced."""
    inner = ENGINE

    class Wrapped:
        def __getattr__(self, name):
            return getattr(inner, name)

        def process_run(self, fixes, *a, **k):
            r = inner.process_run(fixes, *a, **k)
            if not when(fixes):
                return r
            d = dict(distance_m=r.distance_m, moving_seconds=r.moving_seconds, loops=r.loops, cells=r.cells, flags=r.flags)
            d.update(changes)
            return types.SimpleNamespace(**d)

    engine_adapter.set_engine(Wrapped())


def lenient(client):
    """A client that returns 500 responses instead of re-raising server exceptions."""
    return TestClient(client.app, raise_server_exceptions=False)


__all__ = ["dataclasses"]
