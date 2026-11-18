"""Shared vocabulary and helpers for the Phase 1a social features (docs/PHASE1_SPEC.md 0.1-0.3).

Every route uses these predicates; none re-implements them.
"""

from __future__ import annotations

import base64
import json
from typing import Any

from fastapi import Depends, HTTPException

from . import auth
from . import engine_adapter as eng
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


# ---------------------------------------------------------------- battle events: who may be named
def event_visible(ev: dict, now: int, delay_ms: int) -> bool:
    """Nobody (the two parties included) learns of a battle before the map shows it."""
    return now >= ev["at"] + delay_ms


async def name_ok_many(
    res: Resources, viewer: str, pairs: list[tuple[dict, str | None]]
) -> tuple[list[bool], dict[str, dict]]:
    """name_ok(ev, user_id) for many (event, user) pairs with one users query and one blocks query.

    The named user may be shown for the event when K-anonymity held at claim time (`ev.k_ok`), the cell is not in any
    of their current home zones, they are a live user with a visible name, and they are not blocked with the viewer.
    Returns the answers (aligned with `pairs`) and the live users by id (to build UserRefs)."""
    ids = {u for _, u in pairs if u}
    users = await live_users(res, ids)
    hidden_from = await blocked_with(res, viewer, ids)
    zones = {
        uid: [(z["lat"], z["lng"], z["radius_m"]) for z in u.get("home_zones", [])] for uid, u in users.items()
    }
    out: list[bool] = []
    for ev, uid in pairs:
        ok = bool(
            uid
            and ev.get("k_ok")
            and uid in users
            and not users[uid].get("name_hidden")
            and uid not in hidden_from
            and not (zones[uid] and eng.in_home_zone(ev["cell"], zones[uid]))
        )
        out.append(ok)
    return out, users


async def follow_flags(res: Resources, viewer: str, ids: Any) -> tuple[set[str], set[str]]:
    """(ids the viewer follows, ids that follow the viewer) among `ids`, two queries."""
    wanted = sorted(set(ids) - {viewer})
    if not wanted:
        return set(), set()
    f = res.db.follows
    mine = {r["followee_id"] async for r in f.find({"follower_id": viewer, "followee_id": {"$in": wanted}})}
    theirs = {r["follower_id"] async for r in f.find({"followee_id": viewer, "follower_id": {"$in": wanted}})}
    return mine, theirs


def list_item(user: dict, viewer: str, following: set[str], followers: set[str]) -> dict:
    return {
        "id": user["_id"],
        "name": user_ref(user, viewer)["name"],
        "is_following": user["_id"] in following,
        "follows_me": user["_id"] in followers,
    }


# ---------------------------------------------------------------- runs
def published(run: dict, viewer: str, now: int, delay_ms: int) -> bool:
    return viewer == run["user_id"] or now >= run.get("processed_at", 0) + delay_ms


async def can_view_run(res: Resources, viewer: str, run: dict | None) -> bool:
    """Whether `viewer` may see this run's card (so kudos, comments and reports of it): accepted, not hidden by
    moderation, owner is a live user, not blocked, and the viewer is the owner or follows them and the run is
    published. Runs from before phase 1a (no claimed_cells) are not in anybody else's feed, so not here either."""
    if run is None or run.get("status") != "accepted" or run.get("hidden"):
        return False
    owner = run["user_id"]
    if not live_user(await res.db.users.find_one({"_id": owner})):
        return False
    if owner == viewer:
        return True
    if await blocked(res, viewer, owner) or "claimed_cells" not in run:
        return False
    if await res.db.follows.find_one({"_id": f"{viewer}:{owner}"}, {"_id": 1}) is None:
        return False
    return published(run, viewer, res.clock(), res.settings.publish_delay_seconds * 1000)


async def visible_run(res: Resources, viewer: str, run_id: str) -> dict:
    """The run document, or the one 404 (unknown, not published, not followed, hidden, blocked ... look alike)."""
    run = await res.db.runs.find_one({"_id": run_id})
    if not await can_view_run(res, viewer, run):
        raise not_found()
    return run  # type: ignore[return-value]
