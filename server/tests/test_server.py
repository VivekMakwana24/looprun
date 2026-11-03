from __future__ import annotations

import threading
import uuid

import pytest
from starlette.websockets import WebSocketDisconnect

from .conftest import cells_of, db_run, hdr, login, run_loop, square_fixes, upload, with_flag


# ------------------------------------------------------------------ auth / health
def test_healthz(client):
    assert client.get("/healthz").status_code == 200


def test_dev_auth_flow(client):
    a = login(client, "alice")
    again = login(client, "alice")
    assert a["_uid"] == again["_uid"]
    assert login(client, "bob")["_uid"] != a["_uid"]
    assert client.get("/v1/cells", params={"bbox": "8.6,49.9,8.7,50.0"}).status_code == 401
    assert (
        client.get(
            "/v1/cells", params={"bbox": "8.6,49.9,8.7,50.0"}, headers={"Authorization": "Bearer junk"}
        ).status_code
        == 401
    )
    assert client.post("/v1/auth/google", json={"id_token": "dev:bad name!"}).status_code == 401
    assert client.post("/v1/auth/google", json={"id_token": "nonsense"}).status_code in (401, 503)


def test_dev_token_rejected_in_production_mode_and_google_path(make_app):
    def verifier(token, client_id):
        assert client_id == "cid"
        if token != "good":
            raise ValueError("bad")
        return {"sub": "123", "given_name": "Gina"}

    c = make_app(dev_auth=False, google_client_id="cid", google_verifier=verifier)
    assert c.post("/v1/auth/google", json={"id_token": "dev:alice"}).status_code == 401
    assert c.post("/v1/auth/google", json={"id_token": "bad"}).status_code == 401
    r = c.post("/v1/auth/google", json={"id_token": "good"})
    assert r.status_code == 200 and r.json()["user"]["name"] == "Gina"


# ------------------------------------------------------------------ uploads
def test_upload_is_idempotent(client):
    h = login(client, "alice")
    fixes = square_fixes()
    rid, r1 = upload(client, h, fixes)
    _, r2 = upload(client, h, fixes, run_id=rid)
    assert r1.json() == r2.json()
    assert r1.json()["status"] == "accepted"
    assert db_run(client, lambda db: db.runs.count_documents({})) == 1
    assert db_run(client, lambda db: db.cell_power.count_documents({})) == r1.json()["cells_claimed"]
    # another user cannot take over the id
    b = login(client, "bob")
    upload(client, b, fixes, run_id=rid, expect=409)
    assert client.get(f"/v1/runs/{rid}", headers=hdr(b)).status_code == 404


def test_too_many_fixes_413(client):
    h = login(client, "alice")
    fixes = [{"lat": 50.0, "lng": 8.7, "t": i, "acc": 5.0} for i in range(20001)]
    upload(client, h, fixes, expect=413)
    assert db_run(client, lambda db: db.runs.count_documents({})) == 0


def test_validation_422(client):
    h = login(client, "alice")
    r = client.post("/v1/runs", json={"id": "nope", "started_at": 1, "ended_at": 2, "fixes": []}, headers=hdr(h))
    assert r.status_code == 422


def test_rate_limit_429(make_app):
    c = make_app(run_rate_limit=2)
    h = login(c, "alice")
    tiny = [{"lat": 50.0, "lng": 8.7, "t": i * 1000, "acc": 5.0} for i in range(3)]
    upload(c, h, tiny)
    upload(c, h, tiny)
    _, r = upload(c, h, tiny, expect=429)
    assert "retry-after" in r.headers
    # another user is unaffected
    upload(c, login(c, "bob"), tiny)


# ------------------------------------------------------------------ processing / ownership
def test_processing_creates_cells_and_ownership(client):
    h = login(client, "alice")
    st = run_loop(client, h)
    assert st["status"] == "accepted"
    assert st["cells_claimed"] > 3 and st["cells_taken_from_others"] == 0
    assert st["distance_m"] > 1000 and st["moving_seconds"] > 300 and st["loops"]
    cells = cells_of(client, h)
    assert len(cells) == st["cells_claimed"]
    assert all(c["mine"] and not c["hidden"] and c["owner"]["name"] == "alice" for c in cells)


def test_hard_flag_run_pending_review_no_cells(client):
    h = login(client, "alice")
    st = run_loop(client, h, mock_every=7)
    assert st["status"] == "pending_review"
    assert st["cells_claimed"] == 0
    assert any(f["code"] == "mock_location" and f["severity"] == "hard" for f in st["flags"])
    assert db_run(client, lambda db: db.cells.count_documents({})) == 0
    assert db_run(client, lambda db: db.cell_power.count_documents({})) == 0


def test_challenger_needs_more_power_than_owner(client):
    a, b = login(client, "alice"), login(client, "bob")
    first = run_loop(client, a, speed=3.0)  # ~9 moving minutes
    n = first["cells_claimed"]
    fast = run_loop(client, b, speed=5.0)  # fewer minutes -> less credit per cell
    assert fast["cells_claimed"] == 0 and fast["cells_taken_from_others"] == 0
    assert all(c["mine"] for c in cells_of(client, a))
    slow = run_loop(client, b, speed=1.5)  # many more minutes
    assert slow["cells_taken_from_others"] == n and slow["cells_claimed"] == n
    assert not any(c["mine"] for c in cells_of(client, a))
    assert all(c["mine"] for c in cells_of(client, b))


def test_power_fades_on_read_so_a_later_equal_run_wins(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    clock.advance(days=20)  # 13 days past grace: alice's power is ~0.53x
    st = run_loop(client, b)
    assert st["cells_taken_from_others"] == st["cells_claimed"] > 0


def test_freeze_stops_fading(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    r = client.post("/v1/me/freeze", json={"days": 30}, headers=hdr(a))
    assert r.status_code == 200 and r.json()["freeze_until"] == clock.now + 30 * 86_400_000
    clock.advance(days=20)
    st = run_loop(client, b)  # equal power only ties, ties keep the owner
    assert st["cells_claimed"] == 0


def test_freeze_endpoint_limits(client):
    h = login(client, "alice")
    assert client.post("/v1/me/freeze", json={"days": 31}, headers=hdr(h)).status_code == 422
    assert client.post("/v1/me/freeze", json={"days": -1}, headers=hdr(h)).status_code == 422
    assert client.post("/v1/me/freeze", json={"days": 5}, headers=hdr(h)).json()["freeze_until"]
    assert client.post("/v1/me/freeze", json={"days": 0}, headers=hdr(h)).json() == {"freeze_until": None}


# ------------------------------------------------------------------ privacy
def _three_users_same_loop(client):
    hs = [login(client, n) for n in ("alice", "bob", "carol")]
    for h in hs:
        run_loop(client, h)
    return hs


def test_k3_hides_owner_until_three_users_nearby(client):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    run_loop(client, b)
    seen = cells_of(client, b)
    assert seen and all(c["hidden"] and c["owner"] is None and not c["mine"] for c in seen)
    carol = login(client, "carol")
    run_loop(client, carol)
    seen = cells_of(client, b)
    assert all(not c["hidden"] and c["owner"]["name"] == "alice" for c in seen)


def test_k_is_configurable(make_app):
    c = make_app(privacy_min_users=2)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    run_loop(c, b)
    assert all(not x["hidden"] for x in cells_of(c, b))


def test_home_zone_cells_never_reveal_owner(client):
    a, b, _ = _three_users_same_loop(client)
    assert all(x["owner"] for x in cells_of(client, b))
    zones = {"zones": [{"lat": 50.0013, "lng": 8.7028, "radius_m": 1000}]}
    assert client.put("/v1/me/home-zones", json=zones, headers=hdr(a)).status_code == 204
    seen = cells_of(client, b)
    assert seen and all(x["hidden"] and x["owner"] is None for x in seen)
    assert all(x["mine"] and x["owner"] for x in cells_of(client, a))  # the owner still sees their own
    bad = {"zones": [{"lat": 50, "lng": 8.7, "radius_m": 10}]}
    assert client.put("/v1/me/home-zones", json=bad, headers=hdr(a)).status_code == 422
    too_many = {"zones": [{"lat": 50, "lng": 8.7, "radius_m": 100}] * 6}
    assert client.put("/v1/me/home-zones", json=too_many, headers=hdr(a)).status_code == 422


def test_delayed_publishing(make_app, clock):
    c = make_app(publish_delay_seconds=1800)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    assert len(cells_of(c, a)) > 3  # mine at once
    assert cells_of(c, b) == []  # others see nothing yet
    clock.advance(seconds=1801)
    assert len(cells_of(c, b)) == len(cells_of(c, a))


def test_bbox_validation(client):
    h = login(client, "alice")
    for bbox in ("8.0,50.0,8.5,50.1", "8.7,50.0,8.8,50.3", "a,b,c,d", "1,2,3", "8.8,50.0,8.7,50.1"):
        assert client.get("/v1/cells", params={"bbox": bbox}, headers=hdr(h)).status_code == 422, bbox
    assert client.get("/v1/cells", params={"bbox": "8.6,49.9,8.8,50.1"}, headers=hdr(h)).status_code == 200
    assert client.get("/v1/cells", headers=hdr(h)).status_code == 422


# ------------------------------------------------------------------ leaderboard
def test_leaderboard_ordering(client, clock):
    hs = {n: login(client, n) for n in ("alice", "bob", "carol")}
    sizes = {"alice": (50.0, 500), "bob": (50.2, 300), "carol": (50.4, 400)}
    claimed = {n: run_loop(client, hs[n], lat=lat, side_m=side)["cells_claimed"] for n, (lat, side) in sizes.items()}
    r = client.get("/v1/leaderboard/weekly", headers=hdr(hs["bob"])).json()
    assert [e["user"]["name"] for e in r["entries"]] == ["alice", "carol", "bob"]
    assert [e["rank"] for e in r["entries"]] == [1, 2, 3]
    assert [e["cells"] for e in r["entries"]] == [claimed["alice"], claimed["carol"], claimed["bob"]]
    assert r["week"].startswith("2027-W") or "-W" in r["week"]


def test_leaderboard_excludes_implausible_loop_awaiting_review(client):
    hs = {n: login(client, n) for n in ("alice", "bob")}
    with_flag("implausible_loop", "soft", lambda fixes: fixes[0].lat > 50.3)
    run_loop(client, hs["alice"], lat=50.0, side_m=300)
    flagged = run_loop(client, hs["bob"], lat=50.5, side_m=500)
    assert flagged["status"] == "accepted" and any(f["code"] == "implausible_loop" for f in flagged["flags"])
    names = [
        e["user"]["name"] for e in client.get("/v1/leaderboard/weekly", headers=hdr(hs["alice"])).json()["entries"]
    ]
    assert names == ["alice"]


# ------------------------------------------------------------------ account / reports
def test_delete_me_reassigns_and_clears(client):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    run_loop(client, b)
    n = len(cells_of(client, b))
    assert client.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert client.get("/v1/leaderboard/weekly", headers=hdr(a)).status_code == 401
    assert db_run(client, lambda db: db.runs.count_documents({"user_id": a["_uid"]})) == 0
    assert db_run(client, lambda db: db.cell_power.count_documents({"user_id": a["_uid"]})) == 0
    mine = cells_of(client, b)
    assert len(mine) == n and all(c["mine"] for c in mine)
    # the last owner leaving removes the cells
    assert client.delete("/v1/me", headers=hdr(b)).status_code == 204
    assert db_run(client, lambda db: db.cells.count_documents({})) == 0
    assert db_run(client, lambda db: db.users.count_documents({})) == 0


def test_reports(client):
    h = login(client, "alice")
    ok = client.post(
        "/v1/reports", json={"kind": "run", "target_id": "x", "reason": "looks like a car"}, headers=hdr(h)
    )
    assert ok.status_code == 202
    assert db_run(client, lambda db: db.reports.count_documents({})) == 1
    assert (
        client.post("/v1/reports", json={"kind": "user", "target_id": "x", "reason": "r"}, headers=hdr(h)).status_code
        == 422
    )
    assert (
        client.post(
            "/v1/reports", json={"kind": "cell", "target_id": "x", "reason": "r" * 501}, headers=hdr(h)
        ).status_code
        == 422
    )


# ------------------------------------------------------------------ websocket
def test_websocket_receives_cell_changed(client):
    a, b = login(client, "alice"), login(client, "bob")
    url = f"/v1/live?bbox=8.6,49.9,8.8,50.1&token={a['Authorization'].split()[1]}"
    with client.websocket_connect(url) as ws:
        watchdog = threading.Timer(20, ws.close)
        watchdog.start()
        try:
            rid = str(uuid.uuid4())
            upload(client, b, square_fixes(), run_id=rid)
            msg = ws.receive_json()
        finally:
            watchdog.cancel()
    assert msg["type"] == "cell_changed" and msg["mine"] is False
    assert msg["owner"] is None  # only one user nearby: hidden, never sent with an owner
    assert db_run(client, lambda db: db.cells.count_documents({"_id": msg["cell"]})) == 1


def test_websocket_rejects_bad_token_and_big_bbox(client):
    for url in ("/v1/live?bbox=8.6,49.9,8.8,50.1&token=junk", "/v1/live?bbox=8.6,49.9,8.8,50.1"):
        with pytest.raises(WebSocketDisconnect), client.websocket_connect(url):
            pass
    h = login(client, "alice")
    tok = h["Authorization"].split()[1]
    with pytest.raises(WebSocketDisconnect), client.websocket_connect(f"/v1/live?bbox=8,49,9,51&token={tok}"):
        pass


# ------------------------------------------------------------------ freeze settlement (engine/NOTES.md #10)
def test_ending_a_freeze_shifts_updated_at_by_frozen_time(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    t_run = clock.now
    client.post("/v1/me/freeze", json={"days": 30}, headers=hdr(a))
    clock.advance(days=20)
    assert client.post("/v1/me/freeze", json={"days": 0}, headers=hdr(a)).json() == {"freeze_until": None}
    stamps = db_run(client, lambda db: db.cell_power.distinct("updated_at", {"user_id": a["_uid"]}))
    assert stamps == [t_run + 20 * 86_400_000]
    clock.advance(days=5)  # 5 days since the freeze ended: still inside the grace period
    assert run_loop(client, b)["cells_claimed"] == 0


def test_expired_freeze_is_settled_lazily(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    client.post("/v1/me/freeze", json={"days": 10}, headers=hdr(a))
    clock.advance(days=10)  # freeze just ran out; nobody called days=0
    assert run_loop(client, b)["cells_claimed"] == 0  # alice's 10 frozen days were not held against her
    u = db_run(client, lambda db: db.users.find_one({"_id": a["_uid"]}))
    assert u["freeze_until"] is None


def test_without_freeze_same_gap_loses_cells(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    run_loop(client, a)
    clock.advance(days=10 + 10)
    assert run_loop(client, b)["cells_claimed"] > 0
