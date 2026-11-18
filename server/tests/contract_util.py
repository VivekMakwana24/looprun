"""Shared helpers for tests that compare the app with docs/CONTRACT.openapi.yaml."""

from __future__ import annotations

import pathlib
import re

import yaml

CONTRACT_PATH = pathlib.Path(__file__).resolve().parents[2] / "docs" / "CONTRACT.openapi.yaml"

# Operations added by Phase 1a (docs/PHASE1_SPEC.md). The pre-1a tests check every other operation strictly; the
# Phase 1a contract test (test_phase1a_contract.py) checks all of them.
PHASE1A_OPS = {
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
    ("/reports", "post"),  # new kinds and the 404
}


def load_contract() -> dict:
    return yaml.safe_load(CONTRACT_PATH.read_text())


def shape(path: str) -> str:
    """'/runs/{id}/comments/{cid}' -> '/runs/{}/comments/{}' (parameter names differ between contract and app)."""
    return re.sub(r"\{[^}]*\}", "{}", path)


def app_operations(app) -> dict[tuple[str, str], dict]:
    """(shape of the path without the /v1 prefix, method) -> generated OpenAPI operation."""
    out = {}
    for p, ops in app.openapi()["paths"].items():
        for m, op in ops.items():
            out[(shape(p.removeprefix("/v1")), m)] = op
    return out


def contract_operations() -> dict[tuple[str, str], tuple[str, dict]]:
    """(shape, method) -> (contract path, operation); the WebSocket is left out."""
    return {
        (shape(p), m): (p, op) for p, ops in load_contract()["paths"].items() if p != "/live" for m, op in ops.items()
    }
