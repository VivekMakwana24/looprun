"""Shared vocabulary and helpers for the Phase 1a social features (docs/PHASE1_SPEC.md 0.1-0.3).

Every route uses these predicates; none re-implements them.
"""

from __future__ import annotations

import base64
import json
from typing import Any

from fastapi import Depends, HTTPException

from . import auth
from .profanity import name_key  # noqa: F401 - re-exported
from .ratelimit import hit_rate_limit
from .resources import Resources


# ---------------------------------------------------------------- errors
def err(status: int, code: str, message: str, headers: dict[str, str] | None = None) -> HTTPException:
    """Error body of every phase 1a route: {"detail": {"code": "<slug>", "message": "<text>"}}."""
    return HTTPException(status, {"code": code, "message": message}, headers=headers)


def not_found() -> HTTPException:
    """One body for every kind of 'not visible to you', so existence leaks nothing."""
    return err(404, "not_found", "Not found")


async def limited(res: Resources, scope: str, user_id: str, limit: int, window_s: int) -> None:
    retry = await hit_rate_limit(res, scope, user_id, limit, window_s)
    if retry is not None:
        raise err(429, "rate_limited", "Too many requests", {"Retry-After": str(retry)})


async def reader(user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)) -> dict:
    """Dependency of every phase 1a read route: authenticated and inside the shared read rate limit."""
    await limited(res, "social_read", user["_id"], res.settings.social_read_rate, 60)
    return user


# ---------------------------------------------------------------- names
def display_name(user: dict) -> str:
    """The name shown to somebody else: the real one, or Runner-xxxx when moderation hid it."""
    if user.get("name_hidden"):
        return "Runner-" + user["_id"][:4]
    return user["name"]


def user_ref(user: dict, viewer_id: str | None = None) -> dict:
    """{id, name} for a user as `viewer_id` sees them (the owner always sees their own real name)."""
    return {"id": user["_id"], "name": user["name"] if user["_id"] == viewer_id else display_name(user)}


# ---------------------------------------------------------------- predicates
def live_user(user: dict | None) -> bool:
    return user is not None and not user.get("deleting")


async def live_users(res: Resources, ids: Any) -> dict[str, dict]:
    """id -> user document for the ids that exist and are not being deleted."""
    wanted = sorted(set(ids))
    if not wanted:
        return {}
    return {u["_id"]: u async for u in res.db.users.find({"_id": {"$in": wanted}}) if live_user(u)}


async def blocked(res: Resources, a: str, b: str) -> bool:
    return await res.db.blocks.find_one({"_id": {"$in": [f"{a}:{b}", f"{b}:{a}"]}}, {"_id": 1}) is not None


async def blocked_with(res: Resources, viewer: str, others: Any) -> set[str]:
    """The ids among `others` that are blocked with `viewer` in either direction (one query)."""
    ids = sorted(set(others) - {viewer})
    if not ids:
        return set()
    q = {
        "$or": [
            {"blocker_id": viewer, "blocked_id": {"$in": ids}},
            {"blocked_id": viewer, "blocker_id": {"$in": ids}},
        ]
    }
    out: set[str] = set()
    async for b in res.db.blocks.find(q):
        out.add(b["blocked_id"] if b["blocker_id"] == viewer else b["blocker_id"])
    return out


async def visible_user(res: Resources, viewer: str, user_id: str) -> dict:
    """A user another person may look at: exists, not being deleting, not blocked either way. Else 404."""
    u = await res.db.users.find_one({"_id": user_id})
    if not live_user(u) or await blocked(res, viewer, user_id):
        raise not_found()
    return u  # type: ignore[return-value]


# ---------------------------------------------------------------- lists and cursors
def parse_limit(limit: int | None, default: int = 20) -> int:
    if limit is None:
        return default
    if not 1 <= limit <= 50:
        raise err(422, "bad_cursor", "limit must be 1..50")
    return limit


def encode_cursor(*parts: Any) -> str:
    return base64.urlsafe_b64encode(json.dumps(parts, separators=(",", ":")).encode()).decode().rstrip("=")


def decode_cursor(cursor: str | None, n: int) -> list[Any] | None:
    if cursor is None:
        return None
    try:
        data = json.loads(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)))
        if isinstance(data, list) and len(data) == n and all(isinstance(x, (str, int)) for x in data):
            return data
    except (ValueError, TypeError):
        pass
    raise err(422, "bad_cursor", "Bad cursor")
