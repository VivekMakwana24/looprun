"""Phase 1a routes (docs/PHASE1_SPEC.md). Error body: {"detail": {"code": "<slug>", "message": "<text>"}}."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Query

from . import auth, social
from .api import errs
from .cards import build_cards
from .leaderboard import cached_public_counts, weekly_rows
from .models import FollowState, Profile, RunPage, UserList, UserListItem, UserPage
from .notifications import notify
from .resources import Resources

router = APIRouter(prefix="/v1")
DAY_MS = 86_400_000
RIVAL_DAYS = 30
MAX_RIVALS = 50
SEARCH_LIMIT = 20


# ---------------------------------------------------------------- search (before /users/{id})
@router.get("/users/search", response_model=UserList, responses=errs(401, 403, 422, 429))
async def search_users(
    q: str = Query(...), user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> UserList:
    me = user["_id"]
    await social.limited(res, "search", me, res.settings.social_search_rate, 60)
    key = " ".join(q.split()).lower()
    if not 2 <= len(key) <= 30:
        raise social.err(422, "bad_query", "q must be 2 to 30 characters")
    # A range query on the lowercase name: nothing the client sends is ever interpreted as a pattern.
    query = {
        "name_lower": {"$gte": key, "$lt": key + "￿"},
        "_id": {"$ne": me},
        "deleting": {"$ne": True},
        "name_hidden": {"$ne": True},
    }
    found: list[dict] = []
    chunk: list[dict] = []

    async def take() -> bool:
        gone = await social.blocked_with(res, me, [u["_id"] for u in chunk])
        found.extend(u for u in chunk if u["_id"] not in gone)
        chunk.clear()
        return len(found) >= SEARCH_LIMIT

    async for u in res.db.users.find(query).sort([("name_lower", 1), ("_id", 1)]):
        chunk.append(u)
        if len(chunk) >= 50 and await take():
            break
    else:
        await take()
    found = found[:SEARCH_LIMIT]
    mine, theirs = await social.follow_flags(res, me, [u["_id"] for u in found])
    return UserList(users=[UserListItem(**social.list_item(u, me, mine, theirs)) for u in found])


# ---------------------------------------------------------------- profile
@router.get("/users/{user_id}", response_model=Profile, responses=errs(401, 403, 404, 422, 429))
async def get_profile(
    user_id: str, viewer: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)
) -> Profile:
    me = viewer["_id"]
    target = await social.visible_user(res, me, user_id)
    rows, own = await weekly_rows(res, me)
    counts = await cached_public_counts(res)
    f = res.db.follows
    return Profile(
        id=user_id,
        name=social.user_ref(target, me)["name"],
        cells_held=own if user_id == me else counts.get(user_id, 0),
        weekly_rank=next((i + 1 for i, r in enumerate(rows) if r[2] == user_id), None),
        followers_count=await f.count_documents({"followee_id": user_id}),
        following_count=await f.count_documents({"follower_id": user_id}),
        joined_at=target["created_at"],
        is_me=user_id == me,
        is_following=user_id != me and await f.find_one({"_id": f"{me}:{user_id}"}, {"_id": 1}) is not None,
        follows_me=user_id != me and await f.find_one({"_id": f"{user_id}:{me}"}, {"_id": 1}) is not None,
    )


# ---------------------------------------------------------------- follow
async def _followers_count(res: Resources, user_id: str) -> int:
    return await res.db.follows.count_documents({"followee_id": user_id})


@router.put("/users/{user_id}/follow", response_model=FollowState, responses=errs(401, 403, 404, 409, 422, 429))
async def follow(user_id: str, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    s, me = res.settings, user["_id"]
    await social.limited(res, "follow", me, s.social_follow_rate, 3600)
    if user_id == me:
        raise social.err(422, "self", "You cannot follow yourself")
    await social.visible_user(res, me, user_id)
    fid = f"{me}:{user_id}"
    if await res.db.follows.find_one({"_id": fid}, {"_id": 1}) is None:
        if await res.db.follows.count_documents({"follower_id": me}) >= s.social_max_following:
            raise social.err(409, "follow_limit", f"You can follow at most {s.social_max_following} people")
        now = res.clock()
        r = await res.db.follows.update_one(
            {"_id": fid}, {"$setOnInsert": {"follower_id": me, "followee_id": user_id, "at": now}}, upsert=True
        )
        if r.upserted_id is not None:  # a re-follow after an unfollow finds the old notification and adds nothing
            await notify(
                res, f"new_follower:{user_id}:{me}", user_id, "new_follower", me, now + s.publish_delay_seconds * 1000
            )
    return FollowState(is_following=True, followers_count=await _followers_count(res, user_id))


@router.delete("/users/{user_id}/follow", response_model=FollowState, responses=errs(401, 403, 422, 429))
async def unfollow(user_id: str, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    me = user["_id"]
    await social.limited(res, "follow", me, res.settings.social_follow_rate, 3600)
    await res.db.follows.delete_one({"_id": f"{me}:{user_id}"})  # the new_follower notification stays (already sent)
    target = await res.db.users.find_one({"_id": user_id})
    visible = social.live_user(target) and not await social.blocked(res, me, user_id)
    return FollowState(is_following=False, followers_count=await _followers_count(res, user_id) if visible else 0)


async def _follow_page(res: Resources, me: str, mine: bool, limit: int | None, cursor: str | None) -> UserPage:
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    own, other = ("follower_id", "followee_id") if mine else ("followee_id", "follower_id")
    q: dict = {own: me}
    if c:
        q["$or"] = [{"at": {"$lt": c[0]}}, {"at": c[0], "_id": {"$lt": c[1]}}]
    rows = [f async for f in res.db.follows.find(q).sort([("at", -1), ("_id", -1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    users = await social.live_users(res, [r[other] for r in rows])
    shown = [users[r[other]] for r in rows if r[other] in users]
    following, followers = await social.follow_flags(res, me, [u["_id"] for u in shown])
    return UserPage(
        items=[UserListItem(**social.list_item(u, me, following, followers)) for u in shown],
        next_cursor=social.encode_cursor(rows[-1]["at"], rows[-1]["_id"]) if more else None,
    )


@router.get("/me/followers", response_model=UserPage, responses=errs(401, 403, 422, 429))
async def my_followers(
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> UserPage:
    return await _follow_page(res, user["_id"], False, limit, cursor)


@router.get("/me/following", response_model=UserPage, responses=errs(401, 403, 422, 429))
async def my_following(
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> UserPage:
    return await _follow_page(res, user["_id"], True, limit, cursor)


# ---------------------------------------------------------------- rivals
@router.get("/me/rivals", response_model=UserList, responses=errs(401, 403, 429))
async def my_rivals(user: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)) -> UserList:
    """Opponents (either side of a battle) of the last 30 days whose name is visible for the cells involved."""
    me, now = user["_id"], res.clock()
    delay = res.settings.publish_delay_seconds * 1000
    q = {
        "$or": [{"taker_id": me}, {"victim_id": me}],
        "at": {"$gte": now - RIVAL_DAYS * DAY_MS, "$lte": now - delay},
    }
    order: list[str] = []
    seen: set[str] = set()
    users: dict[str, dict] = {}
    cur = res.db.battle_events.find(q).sort([("at", -1), ("_id", -1)])
    batch: list[dict] = []

    async def flush() -> None:
        pairs = [(ev, ev["victim_id"] if ev["taker_id"] == me else ev["taker_id"]) for ev in batch]
        oks, found = await social.name_ok_many(res, me, pairs)
        users.update(found)
        for (_, opp), ok in zip(pairs, oks, strict=True):
            if ok and opp not in seen and len(order) < MAX_RIVALS:
                seen.add(opp)
                order.append(opp)
        batch.clear()

    async for ev in cur:
        batch.append(ev)
        if len(batch) >= 500:
            await flush()
            if len(order) >= MAX_RIVALS:
                break
    if batch:
        await flush()
    mine, theirs = await social.follow_flags(res, me, order)
    return UserList(users=[UserListItem(**social.list_item(users[o], me, mine, theirs)) for o in order])



# ---------------------------------------------------------------- feed and run history
def _before(c: list | None, field: str) -> dict:
    """Mongo condition for 'sorts after the cursor' on (field desc, _id desc)."""
    if not c:
        return {}
    return {"$or": [{field: {"$lt": c[0]}}, {field: c[0], "_id": {"$lt": c[1]}}]}


@router.get("/feed", response_model=RunPage, responses=errs(401, 403, 422, 429))
async def feed(
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> RunPage:
    """Own accepted runs at once, followees' after the publish delay; newest `processed_at` first."""
    s, me, now = res.settings, user["_id"], res.clock()
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    followees = [f["followee_id"] async for f in res.db.follows.find({"follower_id": me}, {"followee_id": 1})]
    live = await social.live_users(res, followees)
    gone = await social.blocked_with(res, me, live)
    ids = sorted(set(live) - gone)[: s.social_max_following]
    published = {
        "user_id": {"$in": ids},
        "processed_at": {"$lte": now - s.publish_delay_seconds * 1000},
        "claimed_cells": {"$exists": True},  # runs from before phase 1a are never shown to others
    }
    parts: list[dict] = [{"$or": [{"user_id": me}, published]}]
    if c:
        parts.append(_before(c, "processed_at"))
    q = {
        "status": "accepted",
        "hidden": {"$ne": True},
        "processed_at": {"$gte": now - s.feed_window_days * DAY_MS},
        "$and": parts,
    }
    rows = [r async for r in res.db.runs.find(q).sort([("processed_at", -1), ("_id", -1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    return RunPage(
        items=await build_cards(res, me, rows),
        next_cursor=social.encode_cursor(rows[-1]["processed_at"], rows[-1]["_id"]) if more else None,
    )


@router.get("/runs", response_model=RunPage, responses=errs(401, 403, 422, 429))
async def run_history(
    limit: int | None = None,
    cursor: str | None = None,
    status: Literal["processing", "accepted", "pending_review", "rejected"] | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> RunPage:
    """The caller's own runs of every status, newest `started_at` first, with their own full numbers."""
    me = user["_id"]
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    q: dict = {"user_id": me, **_before(c, "started_at")}
    if status:
        q["status"] = status
    rows = [r async for r in res.db.runs.find(q).sort([("started_at", -1), ("_id", -1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    return RunPage(
        items=await build_cards(res, me, rows),
        next_cursor=social.encode_cursor(rows[-1]["started_at"], rows[-1]["_id"]) if more else None,
    )
