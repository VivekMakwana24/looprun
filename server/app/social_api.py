"""Phase 1a routes (docs/PHASE1_SPEC.md). Error body: {"detail": {"code": "<slug>", "message": "<text>"}}."""

from __future__ import annotations

import unicodedata
import uuid
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response
from pymongo.errors import DuplicateKeyError

from . import auth, profanity, social
from . import engine_adapter as eng
from .api import errs
from .cards import block_ids, build_cards, count_kudos, event_cutoff
from .leaderboard import cached_public_counts, weekly_rows
from .models import (
    BattleCounts,
    BattleSummary,
    BlockPage,
    Comment,
    CommentPage,
    CommentRequest,
    FollowState,
    KudosState,
    LostCell,
    MarkRead,
    Notification,
    NotificationPage,
    Profile,
    ReportRequest,
    Rival,
    Rivalry,
    RunPage,
    TakeBack,
    UnreadCount,
    UserList,
    UserListItem,
    UserPage,
)
from .notifications import notify
from .processing import expiry
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


# ---------------------------------------------------------------- kudos
async def _kudos_state(res: Resources, me: str, run_id: str) -> KudosState:
    excluded = await block_ids(res, me)
    counts = await count_kudos(res, [run_id], excluded)
    mine = await res.db.kudos.find_one({"_id": f"{run_id}:{me}"}, {"_id": 1}) is not None
    return KudosState(kudos_by_me=mine, kudos_count=counts.get(run_id, 0))


@router.put("/runs/{run_id}/kudos", response_model=KudosState, responses=errs(401, 403, 404, 422, 429))
async def give_kudos(run_id: UUID, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    me, rid = user["_id"], str(run_id)
    await social.limited(res, "kudos", me, res.settings.social_kudos_rate, 3600)
    run = await social.visible_run(res, me, rid)
    if run["user_id"] == me:
        raise social.err(422, "own_run", "You cannot give kudos to your own run")
    now = res.clock()
    r = await res.db.kudos.update_one(
        {"_id": f"{rid}:{me}"},
        {"$setOnInsert": {"run_id": rid, "run_owner_id": run["user_id"], "user_id": me, "at": now}},
        upsert=True,
    )
    if r.upserted_id is not None:
        await notify(
            res, f"kudos:{rid}:{me}", run["user_id"], "kudos", me, now + res.settings.publish_delay_seconds * 1000,
            run_id=rid,
        )  # fmt: skip
    return await _kudos_state(res, me, rid)


@router.delete("/runs/{run_id}/kudos", response_model=KudosState, responses=errs(401, 403, 404, 422, 429))
async def remove_kudos(run_id: UUID, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    me, rid = user["_id"], str(run_id)
    await social.limited(res, "kudos", me, res.settings.social_kudos_rate, 3600)
    await social.visible_run(res, me, rid)
    await res.db.kudos.delete_one({"_id": f"{rid}:{me}"})
    await res.db.notifications.delete_one({"_id": f"kudos:{rid}:{me}"})
    return await _kudos_state(res, me, rid)


# ---------------------------------------------------------------- comments
def _comment_view(doc: dict, author: dict, me: str, run_owner: str) -> Comment:
    return Comment(
        id=doc["_id"],
        run_id=doc["run_id"],
        user=social.user_ref(author, me),  # type: ignore[arg-type]
        text=doc["text"],
        created_at=doc["created_at"],
        hidden=bool(doc.get("hidden")),  # only ever true for the author: nobody else is sent a hidden comment
        can_delete=me in (doc["author_id"], run_owner),
    )


def clean_comment(raw: str) -> str | None:
    text = raw.strip()
    if not 1 <= len(text) <= 500 or any(unicodedata.category(c) in {"Cc", "Cs"} for c in text):
        return None
    return unicodedata.normalize("NFC", text)


@router.get("/runs/{run_id}/comments", response_model=CommentPage, responses=errs(401, 403, 404, 422, 429))
async def list_comments(
    run_id: UUID,
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> CommentPage:
    me, rid = user["_id"], str(run_id)
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    run = await social.visible_run(res, me, rid)
    excluded = await block_ids(res, me)
    q: dict = {
        "run_id": rid,
        "$and": [{"$or": [{"hidden": {"$ne": True}}, {"author_id": me}]}],  # the author still gets their own
        "author_id": {"$nin": sorted(excluded)},
    }
    if c:
        q["$and"].append({"$or": [{"created_at": {"$gt": c[0]}}, {"created_at": c[0], "_id": {"$gt": c[1]}}]})
    rows = [d async for d in res.db.comments.find(q).sort([("created_at", 1), ("_id", 1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    authors = await social.live_users(res, [d["author_id"] for d in rows])
    return CommentPage(
        items=[_comment_view(d, authors[d["author_id"]], me, run["user_id"]) for d in rows if d["author_id"] in authors],  # noqa: E501
        next_cursor=social.encode_cursor(rows[-1]["created_at"], rows[-1]["_id"]) if more else None,
    )


@router.post(
    "/runs/{run_id}/comments", status_code=201, response_model=Comment, responses=errs(401, 403, 404, 409, 422, 429)
)
async def add_comment(
    run_id: UUID, body: CommentRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> Comment:
    s, me, rid = res.settings, user["_id"], str(run_id)
    await social.limited(res, "comment_burst", me, s.social_comment_burst, 60)
    await social.limited(res, "comment", me, s.social_comment_rate, 3600)
    run = await social.visible_run(res, me, rid)
    text = clean_comment(body.text)
    if text is None:
        raise social.err(422, "bad_text", "A comment has 1 to 500 characters and no control characters")
    if s.filter_comments and not profanity.is_allowed(text, s.profanity_list_path):
        raise social.err(422, "text_rejected", "This comment cannot be posted")
    if await res.db.comments.count_documents({"run_id": rid}) >= s.social_max_comments_per_run:
        raise social.err(409, "comment_limit", f"A run has at most {s.social_max_comments_per_run} comments")
    now = res.clock()
    doc = {
        "_id": uuid.uuid4().hex, "run_id": rid, "run_owner_id": run["user_id"], "author_id": me, "text": text,
        "created_at": now, "hidden": False,
    }  # fmt: skip
    await res.db.comments.insert_one(doc)
    if run["user_id"] != me:
        await notify(
            res, f"comment:{doc['_id']}", run["user_id"], "comment", me, now + s.publish_delay_seconds * 1000,
            run_id=rid, comment_id=doc["_id"], comment_preview=text[:80],
        )  # fmt: skip
    return _comment_view(doc, user, me, run["user_id"])


@router.delete(
    "/runs/{run_id}/comments/{comment_id}", status_code=204, responses=errs(401, 403, 404, 422)
)
async def delete_comment(
    run_id: UUID, comment_id: str, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> Response:
    me, rid = user["_id"], str(run_id)
    run = await social.visible_run(res, me, rid)
    doc = await res.db.comments.find_one({"_id": comment_id, "run_id": rid})
    if doc is not None:
        if me not in (doc["author_id"], run["user_id"]):
            raise social.err(403, "forbidden", "Only the author or the owner of the run can delete a comment")
        await res.db.comments.delete_one({"_id": comment_id})
        await res.db.notifications.delete_one({"_id": f"comment:{comment_id}"})
    return Response(status_code=204)


# ---------------------------------------------------------------- battles
SUMMARY_DAYS = 7
TAKE_BACK_MAX = 500


def _window(res: Resources, days: int) -> dict:
    """Events the map already shows (older than the publish delay) from the last `days` days, never older than the
    retention even when Mongo's TTL monitor has not deleted them yet."""
    now = res.clock()
    lo = max(now - days * DAY_MS, event_cutoff(res, now))
    return {"$gte": lo, "$lte": now - res.settings.publish_delay_seconds * 1000}


@router.get("/battles/summary", response_model=BattleSummary, responses=errs(401, 403, 429))
async def battles_summary(user: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)) -> BattleSummary:
    """Cells taken and lost in the last 7 days. Counts include events whose opponent's name is hidden."""
    me, ev = user["_id"], res.db.battle_events
    at = _window(res, SUMMARY_DAYS)
    taken = await ev.count_documents({"taker_id": me, "at": at})
    lost = await ev.count_documents({"victim_id": me, "at": at})
    runs = await ev.distinct("run_id", {"$or": [{"taker_id": me}, {"victim_id": me}], "at": at})
    return BattleSummary(days=SUMMARY_DAYS, taken=taken, lost=lost, net=taken - lost, battles=len(runs))


@router.get("/battles/rivalry", response_model=Rivalry, responses=errs(401, 403, 422, 429))
async def battles_rivalry(
    days: int = Query(30, ge=1, le=90), user: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)
) -> Rivalry:
    """Per opponent whose name is visible for the cells involved; everything else is summed in `unattributed`."""
    me = user["_id"]
    q = {"$or": [{"taker_id": me}, {"victim_id": me}], "at": _window(res, days)}
    events = [e async for e in res.db.battle_events.find(q)]
    pairs = [(e, e["victim_id"] if e["taker_id"] == me else e["taker_id"]) for e in events]
    oks, users = await social.name_ok_many(res, me, pairs)
    per: dict[str, dict] = {}
    hidden = BattleCounts()
    for (e, opp), ok in zip(pairs, oks, strict=True):
        took = e["taker_id"] == me
        if not ok:
            hidden.taken += took
            hidden.lost += not took
            continue
        row = per.setdefault(opp, {"taken": 0, "lost": 0, "last": 0})
        row["taken" if took else "lost"] += 1
        row["last"] = max(row["last"], e["at"])
    order = sorted(per, key=lambda o: (-(per[o]["taken"] + per[o]["lost"]), -per[o]["last"], o))[:50]
    following, _ = await social.follow_flags(res, me, order)
    return Rivalry(
        days=days,
        rivals=[
            Rival(
                user=social.user_ref(users[o], me),  # type: ignore[arg-type]
                taken=per[o]["taken"],
                lost=per[o]["lost"],
                net=per[o]["taken"] - per[o]["lost"],
                last_battle_at=per[o]["last"],
                is_following=o in following,
            )
            for o in order
        ],
        unattributed=hidden,
    )


@router.get("/battles/take-back", response_model=TakeBack, responses=errs(401, 403, 429))
async def battles_take_back(user: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)) -> TakeBack:
    """Cells the caller lost in the last 7 days that somebody else (or nobody) holds now, newest loss first.
    The taker's run is never sent, and the taker is named only when the map would name them."""
    me = user["_id"]
    q = {"victim_id": me, "at": _window(res, SUMMARY_DAYS)}
    seen: set[str] = set()
    rows: list[dict] = []
    batch: list[dict] = []

    async def flush() -> None:
        fresh = []
        for e in batch:
            if e["cell"] not in seen:  # the latest event of a cell comes first
                seen.add(e["cell"])
                fresh.append(e)
        batch.clear()
        found = res.db.cells.find({"_id": {"$in": [e["cell"] for e in fresh]}}, {"owner_id": 1})
        owners = {d["_id"]: d.get("owner_id") async for d in found}
        rows.extend(e for e in fresh if owners.get(e["cell"]) != me)  # won back: not listed

    async for e in res.db.battle_events.find(q).sort([("at", -1), ("_id", -1)]):
        batch.append(e)
        if len(batch) >= 500:
            await flush()
            if len(rows) >= TAKE_BACK_MAX:
                break
    if batch:
        await flush()
    rows = rows[:TAKE_BACK_MAX]
    oks, takers = await social.name_ok_many(res, me, [(e, e.get("taker_id")) for e in rows])
    out = []
    for e, ok in zip(rows, oks, strict=True):
        lat, lng = eng.cell_centre(e["cell"])
        out.append(
            LostCell(
                cell=e["cell"],
                lat=lat,
                lng=lng,
                boundary=eng.cell_boundary(e["cell"]),
                lost_at=e["at"],
                lost_to=social.user_ref(takers[e["taker_id"]], me) if ok else None,  # type: ignore[arg-type]
            )
        )
    return TakeBack(cells=out)


# ---------------------------------------------------------------- notifications inbox
async def _dead_actors(res: Resources, q: dict) -> set[str]:
    actors = set(await res.db.notifications.distinct("actor_id", q)) - {None}
    return actors - set(await social.live_users(res, actors))


async def _unread(res: Resources, me: str, now: int, excluded: set[str]) -> int:
    base = {"user_id": me, "read": False, "visible_at": {"$lte": now}}
    dead = await _dead_actors(res, base)
    return await res.db.notifications.count_documents({**base, "actor_id": {"$nin": sorted(excluded | dead)}})


async def _notification_items(res: Resources, me: str, rows: list[dict]) -> list[Notification]:
    users = await social.live_users(res, [r["actor_id"] for r in rows if r.get("actor_id")])
    taken = [r for r in rows if r["type"] == "cells_taken"]
    split: dict[str, list[int]] = {}  # notification id -> [named cells, unattributed cells]
    if taken:
        by_run = {r["run_id"]: r["_id"] for r in taken}
        events = [e async for e in res.db.battle_events.find({"run_id": {"$in": list(by_run)}, "victim_id": me})]
        oks, _ = await social.name_ok_many(res, me, [(e, e["taker_id"]) for e in events])
        for e, ok in zip(events, oks, strict=True):
            split.setdefault(by_run[e["run_id"]], [0, 0])[0 if ok else 1] += 1
    out: list[Notification] = []
    for r in rows:
        actor = users.get(r.get("actor_id"))
        if actor is None:
            continue  # the actor is gone: nothing to show
        item = Notification(
            id=r["_id"], type=r["type"], created_at=r["visible_at"], read=bool(r["read"]),
            actor=social.user_ref(actor, me),  # type: ignore[arg-type]
            run_id=r.get("run_id"), comment_id=r.get("comment_id"), comment_preview=r.get("comment_preview"),
        )  # fmt: skip
        if r["type"] == "cells_taken":
            named, hidden = split.get(r["_id"], [0, 0])
            item.cells, item.cells_unattributed = named, hidden
            item.run_id = None  # the taker's run is never sent
            if named == 0:
                item.actor = None
        out.append(item)
    return out


@router.get("/notifications", response_model=NotificationPage, responses=errs(401, 403, 422, 429))
async def notifications(
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> NotificationPage:
    me, now = user["_id"], res.clock()
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    excluded = await block_ids(res, me)
    q: dict = {"user_id": me, "visible_at": {"$lte": now}, "actor_id": {"$nin": sorted(excluded)}}
    if c:
        q["$or"] = [{"visible_at": {"$lt": c[0]}}, {"visible_at": c[0], "_id": {"$lt": c[1]}}]
    rows = [r async for r in res.db.notifications.find(q).sort([("visible_at", -1), ("_id", -1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    return NotificationPage(
        items=await _notification_items(res, me, rows),
        next_cursor=social.encode_cursor(rows[-1]["visible_at"], rows[-1]["_id"]) if more else None,
        unread_count=await _unread(res, me, now, excluded),
    )


@router.get("/notifications/unread-count", response_model=UnreadCount, responses=errs(401, 403, 429))
async def unread_count(user: dict = Depends(social.reader), res: Resources = Depends(auth.get_res)) -> UnreadCount:
    return UnreadCount(unread_count=await _unread(res, user["_id"], res.clock(), await block_ids(res, user["_id"])))


@router.post("/notifications/read", status_code=204, responses=errs(401, 403, 422))
async def mark_read(
    body: MarkRead, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> Response:
    """Exactly one of `ids` (the caller's own; others are ignored) or `all: true`."""
    me, now = user["_id"], res.clock()
    if body.all == bool(body.ids):
        raise social.err(422, "bad_request", "Send either ids or all=true, not both and not neither")
    q: dict = {"user_id": me, "visible_at": {"$lte": now}}
    if not body.all:
        q["_id"] = {"$in": body.ids}
    await res.db.notifications.update_many(q, {"$set": {"read": True}})
    return Response(status_code=204)


# ---------------------------------------------------------------- block
@router.put("/users/{user_id}/block", status_code=204, responses=errs(401, 403, 404, 409, 422, 429))
async def block_user(user_id: str, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    me = user["_id"]
    await social.limited(res, "block", me, res.settings.social_block_rate, 3600)
    if user_id == me:
        raise social.err(422, "self", "You cannot block yourself")
    if not social.live_user(await res.db.users.find_one({"_id": user_id})):
        raise social.not_found()
    if (
        await res.db.blocks.find_one({"_id": f"{me}:{user_id}"}, {"_id": 1}) is None
        and await res.db.blocks.count_documents({"blocker_id": me}) >= res.settings.social_max_blocks
    ):
        raise social.err(409, "block_limit", f"You can block at most {res.settings.social_max_blocks} people")
    await social.apply_block(res, me, user_id)
    return Response(status_code=204)


@router.delete("/users/{user_id}/block", status_code=204, responses=errs(401, 403, 422))
async def unblock_user(user_id: str, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)):
    await res.db.blocks.delete_one({"_id": f"{user['_id']}:{user_id}"})  # follows are not restored
    return Response(status_code=204)


@router.get("/me/blocks", response_model=BlockPage, responses=errs(401, 403, 422, 429))
async def my_blocks(
    limit: int | None = None,
    cursor: str | None = None,
    user: dict = Depends(social.reader),
    res: Resources = Depends(auth.get_res),
) -> BlockPage:
    me = user["_id"]
    n = social.parse_limit(limit)
    c = social.decode_cursor(cursor, 2)
    q: dict = {"blocker_id": me}
    if c:
        q["$or"] = [{"at": {"$lt": c[0]}}, {"at": c[0], "_id": {"$lt": c[1]}}]
    rows = [b async for b in res.db.blocks.find(q).sort([("at", -1), ("_id", -1)]).limit(n + 1)]
    more = len(rows) > n
    rows = rows[:n]
    users = await social.live_users(res, [r["blocked_id"] for r in rows])
    return BlockPage(
        items=[social.user_ref(users[r["blocked_id"]], me) for r in rows if r["blocked_id"] in users],  # type: ignore[misc]
        next_cursor=social.encode_cursor(rows[-1]["at"], rows[-1]["_id"]) if more else None,
    )


# ---------------------------------------------------------------- reports
@router.post("/reports", status_code=202, responses=errs(401, 403, 404, 422, 429))
async def report(
    body: ReportRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> dict:
    """Kinds run and cell are stored as before. user, comment and run_card must be visible to the reporter (else 404),
    cannot target oneself (422), keep a snapshot as evidence and are recorded once per reporter and target."""
    me = user["_id"]
    await social.limited(res, "reports", me, 20, 3600)  # one shared limit for every kind
    doc: dict = {
        "reporter_id": me,
        "kind": body.kind,
        "target_id": body.target_id,
        "reason": body.reason,
        "created_at": res.clock(),
        "expire_at": expiry(res, res.settings.reports_retention_days),  # TTL index purges it
        "state": "open",
    }
    if body.kind in ("user", "comment", "run_card"):
        owner, snapshot = await _report_target(res, me, body.kind, body.target_id)
        doc.update(target_owner_id=owner, snapshot=snapshot, resolved_at=None)
        if await res.db.reports.find_one({"reporter_id": me, "kind": body.kind, "target_id": body.target_id}):
            return {"status": "recorded"}  # the same report again: nothing new
    try:
        await res.db.reports.insert_one(doc)
    except DuplicateKeyError:
        pass  # a concurrent identical report: the unique partial index keeps one
    return {"status": "recorded"}


async def _report_target(res: Resources, me: str, kind: str, target_id: str) -> tuple[str, object]:
    """(owner user id, snapshot) of a reportable target, or 404 / 422."""
    if kind == "user":
        if target_id == me:
            raise social.err(422, "self", "You cannot report yourself")
        target = await social.visible_user(res, me, target_id)
        return target["_id"], target["name"]
    if kind == "comment":
        comment = await res.db.comments.find_one({"_id": target_id})
        if comment is None or comment.get("hidden"):
            raise social.not_found()
        if comment["author_id"] == me:
            raise social.err(422, "self", "You cannot report your own comment")
        run = await res.db.runs.find_one({"_id": comment["run_id"]})
        author = await res.db.users.find_one({"_id": comment["author_id"]})
        if not await social.can_view_run(res, me, run) or not social.live_user(author):
            raise social.not_found()
        if await social.blocked(res, me, comment["author_id"]):
            raise social.not_found()
        return comment["author_id"], comment["text"]
    run = await res.db.runs.find_one({"_id": target_id})
    if run is None:
        raise social.not_found()
    if run["user_id"] == me:
        raise social.err(422, "self", "You cannot report your own run")
    if not await social.can_view_run(res, me, run):
        raise social.not_found()
    return run["user_id"], (await build_cards(res, me, [run]))[0]  # the card as the reporter saw it: no GPS
