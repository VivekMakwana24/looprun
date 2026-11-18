"""Every Phase 1a operation of docs/CONTRACT.openapi.yaml exists in the app with the same status codes."""

from __future__ import annotations

from .contract_util import PHASE1A_OPS, app_operations, contract_operations

# Operations whose area is not built yet. Each area's commit removes its operations; the list ends empty.
PENDING: set[tuple[str, str]] = {
    ("/runs", "get"),
    ("/me", "patch"),
    ("/users/search", "get"),
    ("/users/{id}", "get"),
    ("/users/{id}/follow", "put"),
    ("/users/{id}/follow", "delete"),
    ("/me/followers", "get"),
    ("/me/following", "get"),
    ("/me/rivals", "get"),
    ("/feed", "get"),
    ("/runs/{id}/kudos", "put"),
    ("/runs/{id}/kudos", "delete"),
    ("/runs/{id}/comments", "get"),
    ("/runs/{id}/comments", "post"),
    ("/runs/{id}/comments/{comment_id}", "delete"),
    ("/battles/summary", "get"),
    ("/battles/rivalry", "get"),
    ("/battles/take-back", "get"),
    ("/notifications", "get"),
    ("/notifications/unread-count", "get"),
    ("/notifications/read", "post"),
    ("/users/{id}/block", "put"),
    ("/users/{id}/block", "delete"),
    ("/me/blocks", "get"),
    ("/reports", "post"),
}

IMPLICIT = {"401", "403", "422"}  # every route has 401/403 (auth); FastAPI adds 422 for any parameter


def test_every_phase1a_operation_matches_the_contract(client):
    app_ops = app_operations(client.app)
    contract = contract_operations()
    checked = 0
    for (sh, method), (path, op) in sorted(contract.items()):
        if (path, method) not in PHASE1A_OPS or (path, method) in PENDING:
            continue
        assert (sh, method) in app_ops, f"{method.upper()} {path} is in the contract but not in the app"
        documented = set(op["responses"])
        generated = set(app_ops[(sh, method)]["responses"])
        ok = {c for c in documented if c.startswith("2")}
        assert {c for c in generated if c.startswith("2")} == ok, (method, path, sorted(generated))
        assert documented <= generated, (method, path, sorted(documented - generated))
        assert generated - documented <= IMPLICIT, (method, path, sorted(generated - documented - IMPLICIT))
        checked += 1
    assert checked == len(PHASE1A_OPS) - len(PENDING)


def test_the_app_has_no_route_outside_the_contract(client):
    contract = {k for k in contract_operations()}
    extra = {k for k in app_operations(client.app) if k not in contract and k[0] not in {"/healthz"}}
    assert not extra, sorted(extra)


def test_phase1a_operation_list_is_in_the_contract():
    contract_paths = {(p, m) for (_, m), (p, _op) in contract_operations().items()}
    assert PHASE1A_OPS <= contract_paths
