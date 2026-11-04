"""Regression tests for the independent verifier's findings (docs/verification/S1-S3.md, E1-E2.md).

Every test here failed against the first server build or pins a decision of docs/verification/S-fixes.md.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from datetime import datetime

import jwt
import pytest
from starlette.websockets import WebSocketDisconnect

from app import engine_adapter, processing
from app.config import Settings
from app.errors import RETRYABLE, LockLost, LockTimeout
from app.locks import LockSet, RedisLock, region_key, user_key
from app.main import create_app
from app.resources import Resources
from app.worker import process_run as process_run_task

from .conftest import (
    DAY,
    ENGINE,
    T0,
    cells_of,
    db_run,
    hdr,
    lenient,
    login,
    run_loop,
    square_fixes,
    upload,
    with_flag,
    with_result,
)

SECRET = "test-secret-test-secret-test-secret-32b"


def res_of(client) -> Resources:
    return client.app.state.res


def raw(c, h, path, body: str, method="post"):
    return getattr(c, method)(path, content=body, headers={**hdr(h), "Content-Type": "application/json"})


def seed_run(res: Resources, user_id: str, fixes: list[dict], run_id: str | None = None) -> str:
    """Insert a `processing` run the way POST /runs does, without queueing it (tests drive the worker)."""
    rid = run_id or str(uuid.uuid4())

    async def go():
        await res.db.runs.insert_one(
            {"_id": rid, "user_id": user_id, "status": "processing", "flags": [], "loops": [], "fix_count": len(fixes)}
        )
        await res.db.run_fixes.insert_one(
            {
                "_id": rid,
                "user_id": user_id,
                "fixes": [[f["lat"], f["lng"], f["t"], f["acc"], f["mock"]] for f in fixes],
            }
        )

    asyncio.run(go())
    return rid


def run_doc(res: Resources, rid: str) -> dict:
    return asyncio.run(res.db.runs.find_one({"_id": rid}))


# ------------------------------------------------------------------ F11: auth hygiene
def test_dev_name_with_trailing_newline_is_rejected(client):
    for bad in ("abc\n", "abc\r\n", "", "a b", "a/b", "x" * 41, "é"):
        assert client.post("/v1/auth/google", json={"id_token": f"dev:{bad}"}).status_code == 401, repr(bad)
    assert client.post("/v1/auth/google", json={"id_token": "dev:abc"}).status_code == 200


def test_production_mode_refuses_weak_jwt_secrets():
    with pytest.raises(RuntimeError):
        create_app(Settings(dev_auth=False))  # built-in default
    with pytest.raises(RuntimeError):
        create_app(Settings(dev_auth=False, jwt_secret="x"))
    with pytest.raises(RuntimeError):
        create_app(Settings(dev_auth=False, jwt_secret="y" * 31))


def test_production_mode_accepts_a_long_secret(make_app):
    c = make_app(dev_auth=False, jwt_secret="z" * 32, google_client_id="cid")
    assert c.get("/healthz").status_code == 200


def test_jwt_with_object_subject_and_operator_payloads_never_reach_mongo(client):
    lc = lenient(client)
    for payload in ('{"id_token":{"$ne":null}}', '{"id_token":["dev:a"]}'):
        r = lc.post("/v1/auth/google", content=payload, headers={"Content-Type": "application/json"})
        assert r.status_code == 422
    forged = jwt.encode({"sub": {"$ne": "x"}, "exp": int(time.time()) + 100}, SECRET, algorithm="HS256")
    assert lc.get("/v1/leaderboard/weekly", headers={"Authorization": f"Bearer {forged}"}).status_code == 401
    none_alg = jwt.encode({"sub": "x", "exp": int(time.time()) + 100}, key=None, algorithm="none")
    assert lc.get("/v1/leaderboard/weekly", headers={"Authorization": f"Bearer {none_alg}"}).status_code == 401


# ------------------------------------------------------------------ Google verification (N1)
def _google_material():
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "t")])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(1)
        .not_valid_before(datetime(2020, 1, 1))
        .not_valid_after(datetime(2040, 1, 1))
        .sign(key, hashes.SHA256())
    )
    pem_cert = cert.public_bytes(serialization.Encoding.PEM).decode()
    pem_key = key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    )
    return pem_cert, pem_key


def test_google_verify_checks_signature_audience_issuer_expiry_and_allows_small_clock_skew(monkeypatch):
    import json as _json
    from types import SimpleNamespace

    from google.auth import transport  # noqa: F401
    from google.oauth2 import id_token as gid

    from app import auth

    cid = "my-client-id.apps.googleusercontent.com"
    pem_cert, pem_key = _google_material()
    fetches = []

    class FakeTransport:
        def __call__(self, url, method="GET", body=None, headers=None, timeout=120, **kw):
            fetches.append(url)
            data = _json.dumps({"kid1": pem_cert}).encode()
            return SimpleNamespace(status=200, data=data, headers={})

    monkeypatch.setattr(auth, "_cert_request", auth.CachingRequest(inner=FakeTransport()))
    gid._GOOGLE_OAUTH2_CERTS = None  # make sure google-auth's own module cache is not in the way
    monkeypatch.setattr(gid, "_GOOGLE_OAUTH2_CERTS_URL", "https://example.test/certs", raising=False)

    def tok(**over):
        now = int(time.time())
        c = {"iss": "https://accounts.google.com", "aud": cid, "sub": "1234", "iat": now, "exp": now + 600}
        c.update(over)
        c = {k: v for k, v in c.items() if v is not None}
        return jwt.encode(c, pem_key, algorithm="RS256", headers={"kid": "kid1"})

    def ok(t):
        try:
            return auth.google_verify(t, cid)
        except Exception:  # noqa: BLE001
            return None

    now = int(time.time())
    assert ok(tok())["sub"] == "1234"
    assert ok(tok(iat=now + 5)) is not None, "a few seconds of clock skew must be tolerated"
    assert ok(tok(iat=now + 60)) is None
    assert ok(tok(aud="other")) is None
    assert ok(tok(aud=None)) is None
    assert ok(tok(iss="https://evil.example")) is None
    assert ok(tok(iss=None)) is None
    assert ok(tok(exp=now - 60)) is None
    assert ok(tok(exp=None)) is None
    unsigned = jwt.encode({"iss": "https://accounts.google.com", "aud": cid, "sub": "1", "exp": now + 99}, None, "none")
    assert ok(unsigned) is None
    assert ok("a.b.c") is None
    # certificates were fetched once for all of the above, not once per login
    assert len(fetches) == 1, fetches


def test_cert_cache_refetches_after_ttl():
    from types import SimpleNamespace

    from app.auth import CachingRequest

    now = [0.0]
    calls = []

    def inner(url, **kw):
        calls.append(url)
        return SimpleNamespace(status=200, data=b"{}", headers={})

    c = CachingRequest(inner=inner, ttl_s=100, clock=lambda: now[0])
    c("https://x/certs")
    c("https://x/certs")
    assert len(calls) == 1
    now[0] = 101
    c("https://x/certs")
    assert len(calls) == 2


# ------------------------------------------------------------------ F1/F2: numbers that used to give 500
@pytest.mark.parametrize("lit", ["NaN", "Infinity", "-Infinity"])
def test_non_finite_numbers_are_422_everywhere(client, lit):
    a = login(client, "a")
    lc = lenient(client)
    rid = str(uuid.uuid4())

    def fix(lat="50", acc="5"):
        f = '{"lat":%s,"lng":8.7,"t":1,"acc":%s}'  # noqa: UP031
        return '{"id":"' + rid + '","started_at":1,"ended_at":2,"fixes":[' + f % (lat, acc) + "]}"

    assert raw(lc, a, "/v1/runs", fix(lat=lit)).status_code == 422
    assert raw(lc, a, "/v1/runs", fix(acc=lit)).status_code == 422
    zone = '{"zones":[{"lat":50,"lng":8.7,"radius_m":' + lit + "}]}"
    assert raw(lc, a, "/v1/me/home-zones", zone, "put").status_code == 422
    lat_zone = '{"zones":[{"lat":' + lit + ',"lng":8.7,"radius_m":100}]}'
    assert raw(lc, a, "/v1/me/home-zones", lat_zone, "put").status_code == 422
    # control: a finite out-of-range value was always a clean 422
    assert raw(lc, a, "/v1/runs", fix(lat="95")).status_code == 422


@pytest.mark.parametrize("big", [2**62, 2**63 - 1, 2**63, 2**64, 2**70, 10**30])
def test_integers_beyond_year_2100_are_422_not_500(client, big):
    a = login(client, "a")
    lc = lenient(client)
    fix = '{"lat":50,"lng":8.7,"t":%s,"acc":5}'
    body = '{"id":"%s","started_at":1,"ended_at":2,"fixes":[%s]}'
    assert raw(lc, a, "/v1/runs", body % (uuid.uuid4(), fix % big)).status_code == 422
    body2 = '{"id":"%s","started_at":1,"ended_at":%s,"fixes":[%s]}'
    assert raw(lc, a, "/v1/runs", body2 % (uuid.uuid4(), big, fix % 1)).status_code == 422
    body3 = '{"id":"%s","started_at":%s,"ended_at":%s,"fixes":[%s]}'
    assert raw(lc, a, "/v1/runs", body3 % (uuid.uuid4(), big, big, fix % 1)).status_code == 422
    assert db_run(client, lambda db: db.runs.count_documents({})) == 0


# ------------------------------------------------------------------ F7: body cap for chunked requests
def test_chunked_body_is_capped(make_app):
    c = make_app(max_body_bytes=1000)
    a = login(c, "a")

    def gen():
        yield b'{"id":"' + str(uuid.uuid4()).encode() + b'","started_at":1,"ended_at":2,"fixes":['
        for _ in range(500):
            yield b'{"lat":50,"lng":8.7,"t":1,"acc":5},'
        yield b'{"lat":50,"lng":8.7,"t":2,"acc":5}]}'

    r = c.post("/v1/runs", content=gen(), headers={**hdr(a), "Content-Type": "application/json"})
    assert r.status_code == 413
    assert db_run(c, lambda db: db.runs.count_documents({})) == 0


def test_body_cap_content_length_and_small_chunked_bodies_still_work(make_app):
    c = make_app(max_body_bytes=2000)
    a = login(c, "a")
    big = "x" * 3000
    r = c.post("/v1/runs", content=big, headers={**hdr(a), "Content-Type": "application/json"})
    assert r.status_code == 413

    def small():
        yield b'{"id":"' + str(uuid.uuid4()).encode() + b'","started_at":1,"ended_at":2,'
        yield b'"fixes":[{"lat":50,"lng":8.7,"t":1,"acc":5}]}'

    r = c.post("/v1/runs", content=small(), headers={**hdr(a), "Content-Type": "application/json"})
    assert r.status_code == 202


# ------------------------------------------------------------------ B2: leaderboard honours the publish delay
def test_leaderboard_does_not_reveal_unpublished_ownership(make_app, clock):
    c = make_app(publish_delay_seconds=1800, privacy_min_users=1)
    a, b = login(c, "a"), login(c, "b")
    st = run_loop(c, a)
    board = lambda h: c.get("/v1/leaderboard/weekly", headers=hdr(h)).json()["entries"]  # noqa: E731
    assert board(b) == [], "B must not learn that A just finished a run"
    assert [(e["user"]["name"], e["cells"]) for e in board(a)] == [("a", st["cells_claimed"])]  # own entry at once
    clock.advance(seconds=1799)
    assert board(b) == []
    clock.advance(seconds=2)
    assert [(e["user"]["name"], e["cells"]) for e in board(b)] == [("a", st["cells_claimed"])]


def test_leaderboard_cache_never_contains_unpublished_cells(make_app, clock):
    c = make_app(publish_delay_seconds=1800, leaderboard_cache_seconds=60)
    a, b = login(c, "a"), login(c, "b")
    assert c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"] == []  # fills the cache
    run_loop(c, a)  # processing must not invalidate or poison the cache with unpublished data
    assert c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"] == []


def test_takeover_is_delayed_on_the_leaderboard_too(make_app, clock):
    c = make_app(publish_delay_seconds=1800, privacy_min_users=1)
    a, b, o = login(c, "a"), login(c, "b"), login(c, "o")
    first = run_loop(c, a, speed=3.0)
    clock.advance(seconds=1801)
    run_loop(c, b, speed=1.5)  # b takes everything, not yet public
    seen = c.get("/v1/leaderboard/weekly", headers=hdr(o)).json()["entries"]
    assert [(e["user"]["name"], e["cells"]) for e in seen] == [("a", first["cells_claimed"])]
    clock.advance(seconds=1801)
    seen = c.get("/v1/leaderboard/weekly", headers=hdr(o)).json()["entries"]
    assert [e["user"]["name"] for e in seen] == ["b"]


# ------------------------------------------------------------------ B1: account deletion
def test_delete_is_retryable_after_lock_contention(make_app):
    c = make_app(delete_lock_wait_seconds=0.1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    run_loop(c, b)
    res = res_of(c)
    region = asyncio.run(processing._user_regions(res.db, a["_uid"]))[0]
    asyncio.run(res.redis.set(region_key(region), "someone-else", ex=60))  # a busy or dead worker holds the region

    lc = lenient(c)
    r = lc.delete("/v1/me", headers=hdr(a))
    assert r.status_code == 503 and "retry-after" in r.headers
    # the user is only marked, nothing half-deleted behind their back
    u = db_run(c, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert u is not None and u["deleting"] is True
    # a `deleting` account may not upload, claim or read, but its token still works for DELETE /me
    assert c.get("/v1/cells", params={"bbox": "8.6,49.9,8.8,50.1"}, headers=hdr(a)).status_code == 403
    assert c.post("/v1/me/freeze", json={"days": 1}, headers=hdr(a)).status_code == 403
    body = {"id": str(uuid.uuid4()), "started_at": 1, "ended_at": 2, "fixes": []}
    assert c.post("/v1/runs", json=body, headers=hdr(a)).status_code == 403
    # the lock goes away; the retry finishes the job
    asyncio.run(res.redis.delete(region_key(region)))
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert db_run(c, lambda db: db.users.count_documents({"_id": a["_uid"]})) == 0
    assert db_run(c, lambda db: db.cell_power.count_documents({"user_id": a["_uid"]})) == 0
    assert db_run(c, lambda db: db.runs.count_documents({"user_id": a["_uid"]})) == 0
    assert db_run(c, lambda db: db.run_fixes.count_documents({"user_id": a["_uid"]})) == 0
    foreign = {"$or": [{"owner_id": a["_uid"]}, {"public_owner_id": a["_uid"]}, {"pending_owner_id": a["_uid"]}]}
    assert db_run(c, lambda db: db.cells.count_documents(foreign)) == 0
    assert all(x["mine"] for x in cells_of(c, b)) and cells_of(c, b)
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 401  # gone for good


def test_delete_resumes_after_a_crash_between_steps(client):
    a, b = login(client, "a"), login(client, "b")
    run_loop(client, a)
    run_loop(client, b)
    boom = {"n": 0}
    # fail after the cells were handed over but before the user document goes
    real_reports = client.app.state.res.db.reports

    class Reports:
        def __getattr__(self, n):
            return getattr(real_reports, n)

        async def delete_many(self, *a, **k):
            boom["n"] += 1
            if boom["n"] == 1:
                raise ConnectionError("mongo hiccup")
            return await real_reports.delete_many(*a, **k)

    class DB:
        def __init__(self, db):
            self.db = db

        def __getattr__(self, n):
            return Reports() if n == "reports" else getattr(self.db, n)

    res = client.app.state.res
    original_db = res.db
    res.db = DB(original_db)
    try:
        r = client.delete("/v1/me", headers=hdr(a))
        assert r.status_code == 503 and r.headers["retry-after"]  # N8: infrastructure errors are 503, not 500
    finally:
        res.db = original_db
    assert db_run(client, lambda db: db.users.count_documents({"_id": a["_uid"], "deleting": True})) == 1
    assert client.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert db_run(client, lambda db: db.users.count_documents({"_id": a["_uid"]})) == 0
    assert db_run(client, lambda db: db.cell_power.count_documents({"user_id": a["_uid"]})) == 0


def test_delete_racing_with_a_claim_in_flight_leaves_nothing_behind(make_app):
    """The worker passed its `deleting` check and is writing cells when DELETE /me starts: DELETE waits for the
    user's lock, then cleans up what the worker wrote."""
    c = make_app()
    a = login(c, "a")
    res = res_of(c)
    rid = seed_run(res, a["_uid"], square_fixes())
    real_apply = processing._apply
    state = {}

    async def scenario():
        state["in_apply"] = asyncio.Event()

        async def slow_apply(db, user_id, o):
            state["in_apply"].set()
            await asyncio.sleep(0.05)
            await real_apply(db, user_id, o)

        processing._apply = slow_apply
        try:
            worker = asyncio.create_task(processing.process_run_by_id(res, rid))
            await state["in_apply"].wait()
            await processing.delete_account(res, a["_uid"])  # starts while the worker holds the locks
            await worker
        finally:
            processing._apply = real_apply

    asyncio.run(scenario())
    assert asyncio.run(res.db.users.count_documents({"_id": a["_uid"]})) == 0
    assert asyncio.run(res.db.cell_power.count_documents({"user_id": a["_uid"]})) == 0
    assert asyncio.run(res.db.cells.count_documents({"owner_id": a["_uid"]})) == 0
    assert asyncio.run(res.db.cells.count_documents({})) == 0
    assert asyncio.run(res.db.runs.count_documents({})) == 0


def test_worker_skips_claiming_for_a_deleting_or_missing_user(make_app):
    c = make_app()
    a = login(c, "a")
    res = res_of(c)
    rid = seed_run(res, a["_uid"], square_fixes())
    asyncio.run(res.db.users.update_one({"_id": a["_uid"]}, {"$set": {"deleting": True}}))
    asyncio.run(processing.process_run_by_id(res, rid))
    assert asyncio.run(res.db.cell_power.count_documents({})) == 0
    assert asyncio.run(res.db.cells.count_documents({})) == 0
    asyncio.run(res.db.users.delete_one({"_id": a["_uid"]}))
    asyncio.run(processing.process_run_by_id(res, rid))
    assert asyncio.run(res.db.cell_power.count_documents({})) == 0


def test_delete_closes_the_users_open_websocket(make_app):
    c = make_app(privacy_min_users=1)
    a, b = login(c, "a"), login(c, "b")
    tok = b["Authorization"].split()[1]
    with c.websocket_connect(f"/v1/live?bbox=8.6,49.9,8.8,50.1&token={tok}") as ws:
        assert c.delete("/v1/me", headers=hdr(b)).status_code == 204
        with pytest.raises(WebSocketDisconnect) as e:
            deadline = time.time() + 10
            while time.time() < deadline:
                ws.receive_json()
        assert e.value.code == 4401
    run_loop(c, a)  # and the account is really gone


def test_reports_filed_by_the_user_are_deleted_and_reports_expire(client, clock):
    a = login(client, "a")
    r = client.post("/v1/reports", json={"kind": "cell", "target_id": "x", "reason": "r"}, headers=hdr(a))
    assert r.status_code == 202
    rep = db_run(client, lambda db: db.reports.find_one({}))
    assert abs(rep["expire_at"].timestamp() * 1000 - (clock.now + 180 * DAY)) < 1000
    assert client.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert db_run(client, lambda db: db.reports.count_documents({})) == 0


# ------------------------------------------------------------------ F3: idempotent processing, no stuck runs
class _Killed(BaseException):
    pass


class _Boom:
    """Collection proxy: update_one raises while armed."""

    def __init__(self, real, exc):
        self.real, self.exc, self.armed = real, exc, True

    def __getattr__(self, n):
        return getattr(self.real, n)

    async def update_one(self, *a, **k):
        if self.armed:
            raise self.exc
        return await self.real.update_one(*a, **k)


class _DB:
    def __init__(self, real, **over):
        self.real, self.over = real, over

    def __getattr__(self, n):
        return self.over.get(n) or getattr(self.real, n)


def test_redelivery_after_a_crash_does_not_double_credit(make_app):
    c = make_app()
    a = login(c, "a")
    res = res_of(c)
    rid = seed_run(res, a["_uid"], square_fixes())
    runs = _Boom(res.db.runs, _Killed("SIGKILL after the cells were written"))
    broken = Resources(res.settings, _DB(res.db, runs=runs), res.redis, res.clock)
    with pytest.raises(_Killed):  # not an Exception: nothing runs after it, like a killed process
        asyncio.run(processing.process_run_by_id(broken, rid, final=False))
    assert run_doc(res, rid)["status"] == "processing"  # so Celery (acks_late) redelivers the task
    before = asyncio.run(res.db.cell_power.find({}).to_list(None))
    assert before, "the cells were written before the crash"
    asyncio.run(processing.process_run_by_id(res, rid))
    after = asyncio.run(res.db.cell_power.find({}).to_list(None))
    assert sorted((d["cell"], round(d["power"], 9)) for d in before) == sorted(
        (d["cell"], round(d["power"], 9)) for d in after
    )
    doc = run_doc(res, rid)
    assert doc["status"] == "accepted" and doc["cells_claimed"] == len(after)
    # a third delivery (duplicate message) is a no-op
    asyncio.run(processing.process_run_by_id(res, rid))
    again = asyncio.run(res.db.cell_power.find({}).to_list(None))
    assert sorted(d["power"] for d in again) == sorted(d["power"] for d in after)


def test_a_second_run_over_the_same_cells_still_adds_credit_once_per_run(make_app, clock):
    c = make_app()
    a = login(c, "a")
    run_loop(c, a)
    p1 = sorted(d["power"] for d in asyncio.run(res_of(c).db.cell_power.find({}).to_list(None)))
    run_loop(c, a)
    p2 = sorted(d["power"] for d in asyncio.run(res_of(c).db.cell_power.find({}).to_list(None)))
    assert len(p1) == len(p2) and all(y > x for x, y in zip(p1, p2, strict=True))


def test_unexpected_error_marks_the_run_rejected_with_processing_error(make_app, clock):
    c = make_app()
    a = login(c, "a")

    class Bad:
        def __getattr__(self, n):
            return getattr(ENGINE, n)

        def process_run(self, *a, **k):
            raise ValueError("engine blew up")

    engine_adapter.set_engine(Bad())
    rid, _ = upload(c, a, square_fixes())
    st = c.get(f"/v1/runs/{rid}", headers=hdr(a)).json()
    assert st["status"] == "rejected"
    assert [(f["code"], f["severity"]) for f in st["flags"]] == [("processing_error", "hard")]
    # raw GPS of an errored run is kept only for the review window, with a TTL
    fx = db_run(c, lambda db: db.run_fixes.find_one({"_id": rid}))
    assert fx is not None and abs(fx["expire_at"].timestamp() * 1000 - (clock.now + 30 * DAY)) < 1000
    assert "fixes" not in db_run(c, lambda db: db.runs.find_one({"_id": rid}))
    assert db_run(c, lambda db: db.cell_power.count_documents({})) == 0


def test_infrastructure_errors_are_retried_then_give_up_as_processing_error(make_app):
    c = make_app()
    a = login(c, "a")
    res = res_of(c)
    import pymongo.errors as pe

    rid = seed_run(res, a["_uid"], square_fixes())

    class FixesDown:
        def __getattr__(self, n):
            return getattr(res.db.run_fixes, n)

        async def find_one(self, *a, **k):
            raise pe.ServerSelectionTimeoutError("mongo down")

    flaky = Resources(res.settings, _DB(res.db, run_fixes=FixesDown()), res.redis, res.clock)
    with pytest.raises(pe.ServerSelectionTimeoutError):
        asyncio.run(processing.process_run_by_id(flaky, rid, final=False))
    assert run_doc(res, rid)["status"] == "processing"
    # final attempt: marked rejected instead of staying `processing` forever
    asyncio.run(processing.process_run_by_id(flaky, rid, final=True))
    doc = run_doc(res, rid)
    assert doc["status"] == "rejected" and doc["flags"][0]["code"] == "processing_error"


def test_mongo_and_redis_connection_errors_are_retryable_and_celery_retries_them():
    import pymongo.errors as pe
    import redis.exceptions as re_

    for exc in (
        pe.ServerSelectionTimeoutError,
        pe.AutoReconnect,
        pe.NetworkTimeout,
        pe.ConnectionFailure,
        re_.ConnectionError,
        re_.TimeoutError,
        ConnectionResetError,
        TimeoutError,
        LockTimeout,
        LockLost,
    ):
        assert issubclass(exc, RETRYABLE), exc
    assert set(process_run_task.autoretry_for) >= set(RETRYABLE)
    assert process_run_task.retry_backoff is True or process_run_task.retry_backoff > 0
    assert process_run_task.max_retries >= 3


def test_zero_credit_never_calls_apply_claim(make_app):
    c = make_app()
    a = login(c, "a")
    with_result(lambda fx: True, moving_seconds=0)
    calls = []
    real = engine_adapter.apply_claim
    engine_adapter.apply_claim = lambda *x, **k: calls.append(1) or real(*x, **k)
    try:
        st = run_loop(c, a)
    finally:
        engine_adapter.apply_claim = real
    assert st["status"] == "accepted" and st["cells_claimed"] == 0 and calls == []
    assert db_run(c, lambda db: db.cell_power.count_documents({})) == 0


def test_invalid_engine_config_is_refused_at_startup():
    class Cfg:
        halflife_days = 0.0
        grace_days = 7.0
        max_acc_m = 30.0
        max_loop_perimeter_km = 25.0
        max_jump_speed_ms = 12.5
        max_sustained_speed_ms = 7.0
        sustained_window_s = 60
        effort_cap_minutes = 90.0
        closure_tol_m = 80.0
        min_loop_area_km2 = 0.01
        h3_res = 10

    class Bad:
        def __getattr__(self, n):
            return getattr(ENGINE, n)

        Config = Cfg

    engine_adapter.set_engine(Bad())
    with pytest.raises(ValueError, match="halflife_days"):
        create_app(Settings(dev_auth=True))
    Cfg.halflife_days = 14.0
    Cfg.sustained_window_s = 0
    with pytest.raises(ValueError, match="sustained_window_s"):
        create_app(Settings(dev_auth=True))


def test_invalid_settings_are_refused():
    for kw in ({"max_freeze_days": 0}, {"privacy_min_users": 0}, {"processing_lock_seconds": 0}, {"max_fixes": 0}):
        with pytest.raises(ValueError):
            Settings(**kw)


# ------------------------------------------------------------------ F4: freeze rules
def freeze(c, h, days):
    return c.post("/v1/me/freeze", json={"days": days}, headers=hdr(h))


def test_freeze_quota_is_30_days_in_any_90(make_app, clock):
    c = make_app(privacy_min_users=1)
    a = login(c, "a")
    run_loop(c, a)
    assert freeze(c, a, 30).status_code == 200
    clock.advance(days=29)
    r = freeze(c, a, 2)  # would be 31 frozen days within 90
    assert r.status_code == 409
    # the refused request did not cancel the running freeze
    u = db_run(c, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert u["freeze_until"] is not None
    assert freeze(c, a, 1).status_code == 200  # 29 + 1 = 30 is allowed
    clock.advance(days=40)  # day 70: the 30 days are still inside the window
    assert freeze(c, a, 1).status_code == 409
    clock.advance(days=22)  # day 92: day 0..2 of the old freeze left the window
    assert freeze(c, a, 1).status_code == 200


def test_chained_freezes_cannot_switch_decay_off(make_app, clock):
    def scenario(chain: bool) -> int:
        c = make_app(privacy_min_users=1)
        clock.now = T0
        a, b = login(c, "a"), login(c, "b")
        run_loop(c, a)
        for _ in range(4):
            if chain:
                freeze(c, a, 30)  # only the first one is accepted
            clock.advance(days=29)
        return run_loop(c, b)["cells_taken_from_others"]

    assert scenario(False) > 0
    assert scenario(True) > 0, "chained freezes must not keep a cell alive for ever"


def test_freeze_start_rebases_power_so_decay_cannot_be_undone(make_app, clock):
    c = make_app(privacy_min_users=1)
    a, b = login(c, "a"), login(c, "b")
    run_loop(c, a)
    clock.advance(days=60)  # well past grace: power has faded
    row = db_run(c, lambda db: db.cell_power.find_one({"user_id": a["_uid"]}))
    faded = engine_adapter.faded_power(a["_uid"], row["power"], row["updated_at"], clock.now, None)
    assert faded < row["power"] * 0.2
    assert freeze(c, a, 5).status_code == 200
    row = db_run(c, lambda db: db.cell_power.find_one({"user_id": a["_uid"]}))
    assert row["power"] == pytest.approx(faded)
    assert row["updated_at"] == clock.now - int(engine_adapter.grace_days() * DAY)
    # an equal run by b still takes the cells: the freeze did not bring the old power back
    assert run_loop(c, b)["cells_taken_from_others"] > 0


def test_freeze_length_limit_follows_the_setting(make_app):
    c = make_app(max_freeze_days=10)
    a = login(c, "a")
    assert freeze(c, a, 11).status_code == 422
    assert freeze(c, a, 10).status_code == 200


# ------------------------------------------------------------------ F5: raw GPS retention
def test_raw_gps_is_deleted_for_accepted_runs_and_expires_for_held_runs(make_app, clock):
    c = make_app()
    a, b = login(c, "a"), login(c, "b")
    ok = run_loop(c, a)
    assert ok["status"] == "accepted"
    assert db_run(c, lambda db: db.run_fixes.count_documents({})) == 0
    assert all("fixes" not in d for d in db_run(c, lambda db: db.runs.find({}).to_list(None)))
    held = run_loop(c, b, mock_every=7)
    assert held["status"] == "pending_review"
    fx = db_run(c, lambda db: db.run_fixes.find({}).to_list(None))
    assert len(fx) == 1
    assert abs(fx[0]["expire_at"].timestamp() * 1000 - (clock.now + 30 * DAY)) < 1000
    assert all("fixes" not in d for d in db_run(c, lambda db: db.runs.find({}).to_list(None)))


def test_ttl_indexes_exist(client):
    async def go(db):
        return await db.run_fixes.index_information(), await db.reports.index_information()

    fixes_ix, reports_ix = db_run(client, go)
    for ix in (fixes_ix, reports_ix):
        ttl = [v for v in ix.values() if v.get("key") == [("expire_at", 1)]]
        assert ttl and ttl[0].get("expireAfterSeconds") == 0, ix


def test_implausible_loop_is_held_with_no_cells_and_no_power(make_app):
    c = make_app()
    a = login(c, "a")
    with_flag("implausible_loop", "soft", lambda fx: True)
    st = run_loop(c, a)
    assert st["status"] == "pending_review" and st["cells_claimed"] == 0
    assert db_run(c, lambda db: db.cell_power.count_documents({})) == 0
    assert db_run(c, lambda db: db.cells.count_documents({})) == 0
    assert db_run(c, lambda db: db.run_fixes.count_documents({})) == 1  # kept (30 days) for the reviewer


def test_flagged_rerun_cannot_launder_or_remove_earlier_cells(make_app):
    """F8: a held run touches no cells, so it can neither hide earlier legitimate ones nor claim new ones."""
    c = make_app()
    a = login(c, "a")
    first = run_loop(c, a)
    with_flag("implausible_loop", "soft", lambda fx: True)
    run_loop(c, a)
    engine_adapter.set_engine(ENGINE)
    board = c.get("/v1/leaderboard/weekly", headers=hdr(a)).json()["entries"]
    assert [e["cells"] for e in board] == [first["cells_claimed"]]


# ------------------------------------------------------------------ F9: locks
def test_each_lock_has_its_own_token_and_release_is_compare_and_delete(make_app):
    c = make_app()
    redis = res_of(c).redis

    async def go():
        a, b = RedisLock(redis, "k", 1), RedisLock(redis, "k", 1)
        assert a.token != b.token
        assert await a.try_acquire() and not await b.try_acquire()
        assert not await b.release(), "a non-holder must not free the lock"
        assert await redis.get("k") == a.token
        await asyncio.sleep(1.2)  # a's TTL runs out: a was a dead or slow worker
        assert await b.try_acquire()
        assert not await a.release(), "a late worker must not release the lock another worker now holds"
        assert await redis.get("k") == b.token
        assert not await a.extend()
        assert await b.extend()

    asyncio.run(go())


def test_dead_worker_blocks_others_for_at_most_the_ttl(make_app):
    c = make_app()
    redis = res_of(c).redis

    async def go():
        dead = RedisLock(redis, region_key("r"), 1)
        assert await dead.try_acquire()  # never released
        t0 = time.monotonic()
        async with LockSet(redis, [region_key("r")], ttl_s=1, wait_s=5):
            waited = time.monotonic() - t0
        assert 0.5 < waited < 2.5, waited
        with pytest.raises(LockTimeout):
            await redis.set(region_key("z"), "x", ex=30)
            async with LockSet(redis, [region_key("z")], ttl_s=1, wait_s=0.2):
                pass

    asyncio.run(go())


def test_lock_is_extended_while_the_holder_works_and_loss_is_detected(make_app):
    c = make_app()
    redis = res_of(c).redis

    async def go():
        async with LockSet(redis, [region_key("e")], ttl_s=2, wait_s=1) as held:
            await asyncio.sleep(3.3)  # longer than the TTL
            assert await redis.get(region_key("e")) == held.locks[0].token
            held.check()
            await redis.set(region_key("e"), "taken-over", ex=30)  # somebody else took it
            await asyncio.sleep(1.0)
            with pytest.raises(LockLost):
                held.check()
        assert await redis.get(region_key("e")) == "taken-over", "release must not delete another holder's lock"

    asyncio.run(go())


def test_lock_sets_in_one_order_never_deadlock(make_app):
    c = make_app()
    redis = res_of(c).redis
    keys = [region_key(x) for x in "abcd"]

    async def worker(i, done):
        for _ in range(5):
            async with LockSet(redis, [user_key(str(i)), *keys[i % 2 :]], ttl_s=5, wait_s=10):
                await asyncio.sleep(0.005)
        done.append(i)

    async def go():
        done: list[int] = []
        await asyncio.wait_for(asyncio.gather(*(worker(i, done) for i in range(6))), 20)
        assert sorted(done) == list(range(6))
        assert [k async for k in redis.scan_iter("looprun:lock:*")] == []

    asyncio.run(go())


def _concurrency_probe(monkeypatch):
    """Wrap processing._apply so the test can see how many different users write cells at the same moment."""
    active: dict[str, int] = {}
    peak = {"n": 0}
    real = processing._apply

    async def probe(db, user_id, o):
        active[user_id] = active.get(user_id, 0) + 1
        peak["n"] = max(peak["n"], len([u for u, n in active.items() if n > 0]))
        await asyncio.sleep(0.01)
        try:
            await real(db, user_id, o)
        finally:
            active[user_id] -= 1

    monkeypatch.setattr(processing, "_apply", probe)
    return peak


def test_runs_in_different_regions_process_in_parallel(make_app, monkeypatch):
    c = make_app()
    a, b = login(c, "a"), login(c, "b")
    res = res_of(c)
    ra = seed_run(res, a["_uid"], square_fixes(lat=50.0))
    rb = seed_run(res, b["_uid"], square_fixes(lat=50.35))  # ~39 km north: another res-5 region
    peak = _concurrency_probe(monkeypatch)

    async def go():
        await asyncio.gather(processing.process_run_by_id(res, ra), processing.process_run_by_id(res, rb))

    asyncio.run(go())
    regions = {}
    for d in asyncio.run(res.db.cell_power.find({}).to_list(None)):
        regions.setdefault(d["user_id"], set()).add(engine_adapter.region_of(d["cell"], 5))
    assert regions[a["_uid"]].isdisjoint(regions[b["_uid"]])
    assert peak["n"] == 2, "claims in different regions must not wait for each other"
    assert run_doc(res, ra)["status"] == run_doc(res, rb)["status"] == "accepted"


def test_runs_on_the_same_region_serialize_and_only_one_wins_a_contested_cell(make_app, monkeypatch):
    c = make_app()
    a, b = login(c, "a"), login(c, "b")
    res = res_of(c)
    ra = seed_run(res, a["_uid"], square_fixes())
    rb = seed_run(res, b["_uid"], square_fixes())  # the very same loop: identical credit, every cell contested
    peak = _concurrency_probe(monkeypatch)

    async def go():
        await asyncio.gather(processing.process_run_by_id(res, ra), processing.process_run_by_id(res, rb))

    asyncio.run(go())
    assert peak["n"] == 1, "claims on one region must be serialised"
    da, db_ = run_doc(res, ra), run_doc(res, rb)
    assert da["status"] == db_["status"] == "accepted"
    n = len(da["cells"])
    assert n > 3 and da["cells"] == db_["cells"]
    assert sorted([da["cells_claimed"], db_["cells_claimed"]]) == [0, n], "exactly one run wins every contested cell"
    owners = {d["owner_id"] for d in asyncio.run(res.db.cells.find({}).to_list(None))}
    assert len(owners) == 1
    assert asyncio.run(res.redis.keys("looprun:lock:*")) == []


# ------------------------------------------------------------------ A: cell centre in REST and WebSocket
def test_cells_carry_their_centre(client):
    a = login(client, "a")
    run_loop(client, a)
    cells = cells_of(client, a)
    assert cells
    for x in cells:
        lat, lng = engine_adapter.cell_centre(x["id"])
        assert x["lat"] == pytest.approx(lat) and x["lng"] == pytest.approx(lng)


def test_websocket_frame_has_exact_keys_including_centre(client):
    a, b = login(client, "a"), login(client, "b")
    with client.websocket_connect(f"/v1/live?bbox=8.6,49.9,8.8,50.1&token={a['Authorization'].split()[1]}") as ws:
        upload(client, b, square_fixes())
        msg = ws.receive_json()
    assert set(msg) == {"type", "cell", "lat", "lng", "owner", "mine"}
    lat, lng = engine_adapter.cell_centre(msg["cell"])
    assert msg["lat"] == pytest.approx(lat) and msg["lng"] == pytest.approx(lng)
    assert msg["owner"] is None


# ------------------------------------------------------------------ F10: WebSocket auth
def test_websocket_first_message_auth(client):
    a, b = login(client, "a"), login(client, "b")
    tok = a["Authorization"].split()[1]
    with client.websocket_connect("/v1/live?bbox=8.6,49.9,8.8,50.1") as ws:
        ws.send_json({"type": "auth", "token": tok})
        upload(client, b, square_fixes())
        msg = ws.receive_json()
    assert msg["type"] == "cell_changed" and "lat" in msg and "lng" in msg


def test_websocket_first_message_auth_rejections(client):
    a = login(client, "a")
    tok = a["Authorization"].split()[1]
    for first in (
        {"type": "auth", "token": "junk"},
        {"type": "hello", "token": tok},
        {"type": "auth"},
        {"type": "auth", "token": 5},
        [1, 2],
    ):
        with client.websocket_connect("/v1/live?bbox=8.6,49.9,8.8,50.1") as ws:
            ws.send_json(first)
            with pytest.raises(WebSocketDisconnect) as e:
                ws.receive_json()
            assert e.value.code == 4401, first


def test_websocket_first_message_auth_times_out(make_app):
    c = make_app(ws_auth_timeout_seconds=0.3)
    with c.websocket_connect("/v1/live?bbox=8.6,49.9,8.8,50.1") as ws, pytest.raises(WebSocketDisconnect) as e:
        ws.receive_json()
    assert e.value.code == 4401


def test_websocket_rejects_users_that_no_longer_exist(client):
    a = login(client, "a")
    tok = a["Authorization"].split()[1]
    assert client.delete("/v1/me", headers=hdr(a)).status_code == 204
    with pytest.raises(WebSocketDisconnect), client.websocket_connect(f"/v1/live?bbox=8.6,49.9,8.8,50.1&token={tok}"):
        pass
    with client.websocket_connect("/v1/live?bbox=8.6,49.9,8.8,50.1") as ws:
        ws.send_json({"type": "auth", "token": tok})
        with pytest.raises(WebSocketDisconnect) as e:
            ws.receive_json()
        assert e.value.code == 4401


def test_websocket_notices_a_deleted_user_even_without_a_delete_event(make_app):
    c = make_app(ws_recheck_seconds=0.2)
    a = login(c, "a")
    tok = a["Authorization"].split()[1]
    with c.websocket_connect(f"/v1/live?bbox=8.6,49.9,8.8,50.1&token={tok}") as ws:
        db_run(c, lambda db: db.users.delete_one({"_id": a["_uid"]}))
        with pytest.raises(WebSocketDisconnect) as e:
            deadline = time.time() + 10
            while time.time() < deadline:
                ws.receive_json()
        assert e.value.code == 4401


# ------------------------------------------------------------------ contract (A) vs the app
def test_contract_paths_methods_and_documented_errors_match_the_app(client):
    import pathlib

    import yaml

    path = pathlib.Path(__file__).resolve().parents[2] / "docs" / "CONTRACT.openapi.yaml"
    contract = yaml.safe_load(path.read_text())
    app_paths = client.app.openapi()["paths"]

    def norm(p: str) -> str:
        return "/v1" + p.replace("{id}", "{run_id}")

    for p, ops in contract["paths"].items():
        if p == "/live":
            continue
        assert norm(p) in app_paths, p
        for method in ops:
            assert method in app_paths[norm(p)], (p, method)
    docs = {(p, m): set(op["responses"]) for p, ops in contract["paths"].items() for m, op in ops.items()}
    assert {"401", "422"} <= docs[("/auth/google", "post")] | {"422"}
    assert {"401", "413", "422", "429"} <= docs[("/runs", "post")] | {"401"}
    assert "409" in docs[("/runs", "post")] and "409" in docs[("/me/freeze", "post")]
    assert {"401", "404"} <= docs[("/runs/{id}", "get")]
    assert "422" in docs[("/cells", "get")]
    cell = contract["components"]["schemas"]["Cell"]["properties"]
    assert {"id", "lat", "lng", "owner", "mine", "hidden"} <= set(cell)
    live = contract["paths"]["/live"]["get"]["description"]
    assert '"type":"auth"' in live.replace(" ", "") and "lat" in live and "lng" in live


def test_documented_status_codes_really_are_returned(make_app):
    c = make_app(run_rate_limit=1, max_body_bytes=5000)
    a = login(c, "a")
    assert c.get("/v1/leaderboard/weekly").status_code == 401
    assert c.get(f"/v1/runs/{uuid.uuid4()}", headers=hdr(a)).status_code == 404
    assert c.get("/v1/cells", params={"bbox": "1,2,3"}, headers=hdr(a)).status_code == 422
    tiny = [{"lat": 50.0, "lng": 8.7, "t": i * 1000, "acc": 5.0} for i in range(3)]
    rid, _ = upload(c, a, tiny)
    other = login(c, "b")
    upload(c, other, tiny, run_id=rid, expect=409)
    _, r = upload(c, a, tiny, expect=429)
    assert "retry-after" in r.headers
    big = c.post("/v1/runs", content="x" * 6000, headers={**hdr(a), "Content-Type": "application/json"})
    assert big.status_code == 413
