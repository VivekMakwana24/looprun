"""Every Phase 1a operation of docs/CONTRACT.openapi.yaml exists in the app, documents the same status codes, and
really returns each of them."""

from __future__ import annotations

from .contract_util import PHASE1A_OPS, app_operations, contract_operations

IMPLICIT = {"401", "403", "422"}  # every route has 401/403 (auth); FastAPI adds 422 for any parameter


def test_every_phase1a_operation_matches_the_contract(client):
    app_ops = app_operations(client.app)
    contract = contract_operations()
    checked = 0
    for (sh, method), (path, op) in sorted(contract.items()):
        if (path, method) not in PHASE1A_OPS:
            continue
        assert (sh, method) in app_ops, f"{method.upper()} {path} is in the contract but not in the app"
        documented = set(op["responses"])
        generated = set(app_ops[(sh, method)]["responses"])
        ok = {c for c in documented if c.startswith("2")}
        assert {c for c in generated if c.startswith("2")} == ok, (method, path, sorted(generated))
        assert documented <= generated, (method, path, sorted(documented - generated))
        assert generated - documented <= IMPLICIT, (method, path, sorted(generated - documented - IMPLICIT))
        checked += 1
    assert checked == len(PHASE1A_OPS)


def test_the_app_has_no_route_outside_the_contract(client):
    contract = {k for k in contract_operations()}
    extra = {k for k in app_operations(client.app) if k not in contract and k[0] not in {"/healthz"}}
    assert not extra, sorted(extra)


def test_phase1a_operation_list_is_in_the_contract():
    contract_paths = {(p, m) for (_, m), (p, _op) in contract_operations().items()}
    assert PHASE1A_OPS <= contract_paths


# ---------------------------------------------------------------- the documented codes are really returned
UUID0 = "00000000-0000-4000-8000-000000000000"
ALL_LIMITS = dict(
    social_follow_rate=1, social_kudos_rate=1, social_comment_rate=1, social_comment_burst=1, social_block_rate=1,
    social_rename_rate=1, social_search_rate=1, social_read_rate=1,
)  # fmt: skip


def _fill(path: str, uid_: str = "x", run: str = UUID0, cid: str = "c") -> str:
    return "/v1" + path.replace("{comment_id}", cid).replace("{id}", run if path.startswith("/runs/") else uid_)


def _send(c, method, path, h=None, json=None, params=None):
    headers = {"Authorization": h["Authorization"]} if h else {}
    return c.request(method.upper(), path, headers=headers, json=json, params=params)


def test_every_documented_phase1a_status_code_is_really_returned(make_app):
    from .conftest import T0, login
    from .phase1a import follow, seed_run, uid, upd

    contract = {(p, m): op for (_, m), (p, op) in contract_operations().items() if (p, m) in PHASE1A_OPS}
    seen: set[tuple[str, str, str]] = set()

    def hit(path, method, code, h, *, json=None, params=None, uid_="x", run=UUID0, cid="c"):
        r = _send(c, method, _fill(path, uid_, run, cid), h, json, params)
        assert r.status_code == code, (method, path, code, r.status_code, r.text[:200])
        seen.add((path, method, str(code)))
        return r

    c = make_app(
        privacy_min_users=1, social_max_following=1, social_max_blocks=1, social_max_comments_per_run=1,
        social_comment_burst=100, social_comment_rate=100, social_rename_rate=100,
    )  # fmt: skip
    a, b, d, gone = login(c, "alice"), login(c, "bob"), login(c, "dora"), login(c, "gina")
    follow(c, a, b)
    rid = seed_run(c, b, at=T0 - 1)
    own = seed_run(c, a, at=T0 - 1)
    ua, ub, ud = uid(a), uid(b), uid(d)

    # success codes
    hit("/runs", "get", 200, a)
    hit("/me", "patch", 200, a, json={"display_name": "Alice A"})
    hit("/users/search", "get", 200, a, params={"q": "bo"})
    hit("/users/{id}", "get", 200, a, uid_=ub)
    hit("/users/{id}/follow", "put", 200, a, uid_=ub)
    hit("/users/{id}/follow", "delete", 200, a, uid_=ub)
    follow(c, a, b)
    for p in ("/me/followers", "/me/following", "/me/rivals", "/feed", "/battles/summary", "/battles/rivalry",
              "/battles/take-back", "/notifications", "/notifications/unread-count", "/me/blocks"):  # fmt: skip
        hit(p, "get", 200, a)
    hit("/runs/{id}/kudos", "put", 200, a, run=rid)
    hit("/runs/{id}/kudos", "delete", 200, a, run=rid)
    hit("/runs/{id}/comments", "get", 200, a, run=rid)
    cid = hit("/runs/{id}/comments", "post", 201, a, run=rid, json={"text": "hi"}).json()["id"]
    hit("/runs/{id}/comments/{comment_id}", "delete", 204, a, run=rid, cid=cid)
    hit("/notifications/read", "post", 204, a, json={"all": True})
    hit("/users/{id}/block", "put", 204, d, uid_=ua)
    hit("/users/{id}/block", "delete", 204, d, uid_=ua)
    hit("/reports", "post", 202, a, json={"kind": "user", "target_id": ub, "reason": "x"})

    # 404, 409, 422
    hit("/users/{id}", "get", 404, a, uid_="f" * 32)
    hit("/users/{id}/follow", "put", 404, a, uid_="f" * 32)
    hit("/users/{id}/follow", "put", 422, a, uid_=ua)
    hit("/users/{id}/follow", "put", 409, a, uid_=ud)  # limit of 1: already following bob
    hit("/runs/{id}/kudos", "put", 404, a)
    hit("/runs/{id}/kudos", "put", 422, a, run=own)
    hit("/runs/{id}/kudos", "delete", 404, a)
    hit("/runs/{id}/comments", "get", 404, a)
    hit("/runs/{id}/comments", "post", 404, a, json={"text": "x"})
    hit("/runs/{id}/comments", "post", 422, a, run=rid, json={"text": "   "})
    hit("/runs/{id}/comments", "post", 201, a, run=rid, json={"text": "one"})
    hit("/runs/{id}/comments", "post", 409, a, run=rid, json={"text": "two"})  # limit of 1 per run
    hit("/runs/{id}/comments", "get", 422, a, run=rid, params={"limit": 0})
    hit("/runs/{id}/comments/{comment_id}", "delete", 404, a)
    third = hit("/runs/{id}/comments", "get", 200, a, run=rid).json()["items"][0]["id"]
    follow(c, d, b)
    hit("/runs/{id}/comments/{comment_id}", "delete", 403, d, run=rid, cid=third)
    hit("/users/{id}/block", "put", 404, a, uid_="f" * 32)
    hit("/users/{id}/block", "put", 422, a, uid_=ua)
    hit("/users/{id}/block", "put", 204, a, uid_=ud)
    hit("/users/{id}/block", "put", 409, a, uid_=ub)  # limit of 1
    hit("/users/search", "get", 422, a, params={"q": "x"})
    hit("/me", "patch", 422, a, json={"display_name": "x"})
    hit("/runs", "get", 422, a, params={"limit": 0})
    for p in ("/me/followers", "/me/following", "/feed", "/notifications", "/me/blocks"):
        hit(p, "get", 422, a, params={"cursor": "!!"})
    hit("/battles/rivalry", "get", 422, a, params={"days": 0})
    hit("/notifications/read", "post", 422, a, json={})
    hit("/reports", "post", 404, a, json={"kind": "user", "target_id": "f" * 32, "reason": "x"})
    hit("/reports", "post", 422, a, json={"kind": "user", "target_id": ua, "reason": "x"})

    # 401 and 403 on every operation
    upd(c, "users", {"_id": uid(gone)}, {"$set": {"deleting": True}})
    for (path, method) in contract:
        hit(path, method, 401, None, json={})
        hit(path, method, 403, gone, json={})

    # 429: a second app where every limit is 1; the second call to each rate-limited operation is refused
    limited = make_app(**ALL_LIMITS)
    x, y = login(limited, "xavier"), login(limited, "yara")
    for (path, method), op in contract.items():
        if "429" not in op["responses"]:
            continue
        if path == "/reports":
            body = {"kind": "user", "target_id": uid(y), "reason": "r"}
        elif "comments" in path:
            body = {"text": "x"}
        elif method == "patch":
            body = {"display_name": "Name"}
        else:
            body = None
        params = {"q": "ya"} if path == "/users/search" else None
        url = _fill(path, uid(y), UUID0, "c")
        for _ in range(21 if path == "/reports" else 2):  # reports are capped at 20 an hour
            r = _send(limited, method, url, x, body, params)
        assert r.status_code == 429 and "retry-after" in r.headers, (method, path, r.status_code)
        seen.add((path, method, "429"))

    missing = {
        (p, m, code)
        for (p, m), op in contract.items()
        for code in op["responses"]
        if (p, m, code) not in seen
    }
    assert not missing, sorted(missing)
