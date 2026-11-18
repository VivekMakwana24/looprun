"""REST routes under /v1 (docs/CONTRACT.openapi.yaml)."""

from __future__ import annotations

import asyncio
import logging
import unicodedata
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pymongo.errors import DuplicateKeyError, PyMongoError
from redis.exceptions import RedisError

from . import auth, profanity, social
from .cellview import build_views
from .errors import RETRYABLE, LockTimeout
from .events import iso_week
from .freeze import quota_ok, rebase_for_freeze, settle_freeze, used_days
from .leaderboard import cached_public_counts, weekly_rows
from .leaderboard import public_counts as _public_counts  # noqa: F401 - kept importable from here
from .models import (
    CellsResponse,
    FreezeRequest,
    FreezeResponse,
    GoogleAuthRequest,
    HomeZonesRequest,
    LeaderboardResponse,
    MeResponse,
    Profile,
    RenameRequest,
    RenameResponse,
    ReportRequest,
    RunStatus,
    RunUpload,
    Session,
    UserRef,
)
from .processing import delete_account, expiry, purge_redis
from .ratelimit import hit_rate_limit
from .resources import Resources
from .worker import enqueue_run

log = logging.getLogger("looprun.api")
router = APIRouter(prefix="/v1")

DAY_MS = 86_400_000

_DESC = {
    401: "Missing, invalid or expired token (or the user no longer exists)",
    403: "The account is being deleted; every route except DELETE /me refuses it",
    404: "Unknown run or not yours",
    409: "Conflict (run id belongs to another user, or the freeze quota would be exceeded)",
    413: "Too many fixes or request body too large (also when sent chunked)",
    422: "Validation error",
    429: "Rate limited; the Retry-After header says how many seconds to wait",
    503: "Service unavailable; retry (see Retry-After where present)",
}


def errs(*codes: int) -> dict[int | str, dict[str, str]]:
    """FastAPI `responses=` entries so app.openapi() lists the same error codes as docs/CONTRACT.openapi.yaml."""
    return {c: {"description": _DESC[c]} for c in codes}


def parse_bbox(raw: str, max_deg: float) -> tuple[float, float, float, float]:
    """'minLng,minLat,maxLng,maxLat' -> floats; ValueError when malformed or larger than max_deg a side."""
    parts = raw.split(",")
    if len(parts) != 4:
        raise ValueError("bbox must be minLng,minLat,maxLng,maxLat")
    min_lng, min_lat, max_lng, max_lat = (float(p) for p in parts)
    if not (-180 <= min_lng <= max_lng <= 180 and -90 <= min_lat <= max_lat <= 90):
        raise ValueError("bbox out of range or inverted")
    if (max_lng - min_lng) > max_deg + 1e-9 or (max_lat - min_lat) > max_deg + 1e-9:
        raise ValueError(f"bbox larger than {max_deg} degrees on a side")
    return min_lng, min_lat, max_lng, max_lat


def run_status(doc: dict) -> RunStatus:
    return RunStatus(
        id=doc["_id"],
        status=doc["status"],
        distance_m=doc.get("distance_m"),
        moving_seconds=doc.get("moving_seconds"),
        loops=doc.get("loops", []),
        cells_claimed=doc.get("cells_claimed", 0),
        cells_taken_from_others=doc.get("cells_taken_from_others", 0),
        flags=doc.get("flags", []),
    )


# ---------------------------------------------------------------- auth
@router.post("/auth/google", response_model=Session, responses=errs(401, 422, 503))
async def auth_google(body: GoogleAuthRequest, request: Request, res: Resources = Depends(auth.get_res)) -> Session:
    subject, name = await auth.identify(res, request.app.state.google_verifier, body.id_token)
    user = await auth.upsert_user(res, subject, name)
    return Session(access_token=auth.create_token(res, user["_id"]), user=UserRef(id=user["_id"], name=user["name"]))


# ---------------------------------------------------------------- runs
@router.post("/runs", status_code=202, response_model=RunStatus, responses=errs(401, 403, 409, 413, 422, 429, 503))
async def upload_run(
    body: RunUpload, response: Response, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> RunStatus:
    s = res.settings
    run_id = str(body.id)
    existing = await res.db.runs.find_one({"_id": run_id})
    if existing is not None:
        return await _repeat_upload(res, user, body, existing)
    if len(body.fixes) > s.max_fixes:
        raise HTTPException(413, f"Too many fixes (max {s.max_fixes})")
    retry = await hit_rate_limit(res, "runs", user["_id"], s.run_rate_limit, s.run_rate_window_seconds)
    if retry is not None:
        raise HTTPException(429, "Too many uploads", headers={"Retry-After": str(retry)})

    doc: dict[str, Any] = {
        "_id": run_id,
        "user_id": user["_id"],
        "started_at": body.started_at,
        "ended_at": body.ended_at,
        "received_at": res.clock(),
        "integrity_token": body.integrity_token,
        "integrity_verdict": "unchecked",  # v1: stored, not verified, never blocks
        "fix_count": len(body.fixes),
        "status": "processing",
        "cells_claimed": 0,
        "cells_taken_from_others": 0,
        "flags": [],
        "loops": [],
    }
    try:
        await res.db.runs.insert_one(doc)
    except DuplicateKeyError:
        again = await res.db.runs.find_one({"_id": run_id})
        if again is None:
            raise HTTPException(409, "Run id already used") from None
        return await _repeat_upload(res, user, body, again)
    try:
        await _store_fixes(res, user["_id"], run_id, body)
    except Exception:
        log.exception("store_fixes_failed", extra={"run_id": run_id})
        await _discard_run(res, run_id)
        raise HTTPException(503, "Storage unavailable") from None
    # The account may have been deleted (or started deleting) between authentication and the insert above:
    # DELETE /me removes runs only once, so look again and clean up after ourselves.
    await _require_live_user(res, user["_id"], run_id)
    try:
        await asyncio.to_thread(enqueue_run, run_id)
    except Exception:
        log.exception("enqueue_failed", extra={"run_id": run_id})
        await _discard_run(res, run_id)  # let the client retry with the same id
        raise HTTPException(503, "Queue unavailable") from None
    current = await res.db.runs.find_one({"_id": run_id})
    return run_status(current or doc)


async def _store_fixes(res: Resources, user_id: str, run_id: str, body: RunUpload) -> None:
    try:
        await res.db.run_fixes.insert_one(
            {
                "_id": run_id,
                "user_id": user_id,
                "fixes": [[f.lat, f.lng, f.t, f.acc, f.mock] for f in body.fixes],
                # even a run stuck in `processing` must not keep raw GPS forever
                "expire_at": expiry(res, res.settings.fixes_retention_days),
            }
        )
    except DuplicateKeyError:
        pass  # a retry of an interrupted upload: the fixes are already there


async def _discard_run(res: Resources, run_id: str) -> None:
    await res.db.run_fixes.delete_one({"_id": run_id})
    await res.db.runs.delete_one({"_id": run_id})


async def _require_live_user(res: Resources, user_id: str, run_id: str) -> None:
    fresh = await res.db.users.find_one({"_id": user_id}, {"deleting": 1})
    if fresh is None or fresh.get("deleting"):
        await _discard_run(res, run_id)
        if fresh is None:
            await purge_redis(res.redis, user_id)  # the rate-limit counter of this very request
            raise HTTPException(401, "Unknown user")
        raise HTTPException(403, "Account is being deleted")


async def _repeat_upload(res: Resources, user: dict, body: RunUpload, existing: dict) -> RunStatus:
    """Same run id again: idempotent, no new run. If the first attempt never got processed (the process died
    between the insert and the enqueue, or the queue lost the message) and has been `processing` for longer than
    run_reenqueue_after_seconds, this retry enqueues it again (processing is idempotent per run id)."""
    s = res.settings
    if existing["user_id"] != user["_id"]:
        raise HTTPException(409, "Run id already used")
    now = res.clock()
    wait_ms = int(s.run_reenqueue_after_seconds * 1000)
    if (
        existing["status"] == "processing"
        and now - existing.get("received_at", 0) > wait_ms
        and now - existing.get("last_enqueued_at", 0) > wait_ms
    ):
        if len(body.fixes) > s.max_fixes:
            raise HTTPException(413, f"Too many fixes (max {s.max_fixes})")
        run_id = existing["_id"]
        await _store_fixes(res, user["_id"], run_id, body)  # only inserts when they are missing
        await _require_live_user(res, user["_id"], run_id)
        try:
            await asyncio.to_thread(enqueue_run, run_id)
        except Exception:
            log.exception("re_enqueue_failed", extra={"run_id": run_id})
            raise HTTPException(503, "Queue unavailable") from None
        await res.db.runs.update_one({"_id": run_id}, {"$set": {"last_enqueued_at": now}})
        existing = await res.db.runs.find_one({"_id": run_id}) or existing
    return run_status(existing)


@router.get("/runs/{run_id}", response_model=RunStatus, responses=errs(401, 403, 404, 422))
async def get_run(
    run_id: UUID, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> RunStatus:
    doc = await res.db.runs.find_one({"_id": str(run_id), "user_id": user["_id"]})
    if doc is None:
        raise HTTPException(404, "Unknown run")
    return run_status(doc)


# ---------------------------------------------------------------- map
@router.get(
    "/cells",
    response_model=CellsResponse,
    response_model_exclude_unset=True,  # `strength` is only sent on the caller's own cells
    responses=errs(401, 403, 422, 429),
)
async def get_cells(
    bbox: str = Query(...), user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> CellsResponse:
    s = res.settings
    try:
        min_lng, min_lat, max_lng, max_lat = parse_bbox(bbox, s.bbox_max_degrees)
    except ValueError as e:
        raise HTTPException(422, str(e)) from None
    retry = await hit_rate_limit(res, "cells", user["_id"], s.cells_rate_limit, s.cells_rate_window_seconds)
    if retry is not None:
        raise HTTPException(429, "Too many map requests", headers={"Retry-After": str(retry)})
    q = {"lat": {"$gte": min_lat, "$lte": max_lat}, "lng": {"$gte": min_lng, "$lte": max_lng}}
    docs = [d async for d in res.db.cells.find(q).limit(s.cells_max_results)]
    return CellsResponse(cells=await build_views(res, docs, user["_id"]))


@router.get("/leaderboard/weekly", response_model=LeaderboardResponse, responses=errs(401, 403))
async def leaderboard(
    user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> LeaderboardResponse:
    week = iso_week(res.clock())
    rows, own = await weekly_rows(res, user["_id"])
    entries = [
        {"rank": i + 1, "user": {"id": uid, "name": name}, "cells": n}
        for i, (n, name, uid) in enumerate(rows[: res.settings.leaderboard_size])
    ]
    # The caller's own place, also when it is below the listed entries.
    my_rank = next((i + 1 for i, r in enumerate(rows) if r[2] == user["_id"]), None)
    return LeaderboardResponse(week=week, entries=entries, me={"rank": my_rank, "cells": own if my_rank else 0})


# ---------------------------------------------------------------- me
def _freeze_status(res: Resources, user: dict, now: int) -> dict:
    s = res.settings
    until = user.get("freeze_until")
    return {
        "freeze_until": until if until is not None and until > now else None,
        "used_days": used_days(user, now, s.freeze_window_days),
        "quota_days": s.freeze_quota_days,
        "window_days": s.freeze_window_days,
    }


@router.get("/me", response_model=MeResponse, responses=errs(401, 403))
async def get_me(user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)) -> MeResponse:
    """The caller's own settings: name, home zones and the state of the decay freeze. Read-only."""
    fresh = await res.db.users.find_one({"_id": user["_id"]}) or user
    return MeResponse(
        user=UserRef(id=fresh["_id"], name=fresh["name"]),
        home_zones=fresh.get("home_zones", []),
        freeze=_freeze_status(res, fresh, res.clock()),
        name_hidden=bool(fresh.get("name_hidden")),
    )


# control, format (zero-width, bidi), surrogate, private use, unassigned
NAME_BAD_CATEGORIES = {"Cc", "Cf", "Cs", "Co", "Cn"}


def clean_display_name(raw: str) -> str | None:
    """Trim, collapse inner whitespace, NFC; None when the name is not allowed (2..30 code points, no control or
    zero-width characters, passes the profanity hook)."""
    if any(unicodedata.category(c) in NAME_BAD_CATEGORIES for c in raw):
        return None
    name = " ".join(unicodedata.normalize("NFC", raw).split())
    return name if 2 <= len(name) <= 30 else None


@router.patch("/me", response_model=RenameResponse, responses=errs(401, 403, 422, 429))
async def rename_me(
    body: RenameRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> RenameResponse:
    """Change the display name (2..30 characters). Clears a moderation hide of the old name."""
    s = res.settings
    await social.limited(res, "rename", user["_id"], s.social_rename_rate, 86_400)
    name = clean_display_name(body.display_name)
    if name is None or not profanity.is_allowed(name, s.profanity_list_path):
        raise social.err(422, "name_rejected", "This name cannot be used")  # same message whatever the rule
    await res.db.users.update_one(
        {"_id": user["_id"]}, {"$set": {"name": name, "name_lower": social.name_key(name), "name_hidden": False}}
    )
    return RenameResponse(user=UserRef(id=user["_id"], name=name))


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


@router.put("/me/home-zones", status_code=204, responses=errs(401, 403, 422))
async def put_home_zones(
    body: HomeZonesRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> Response:
    zones = [z.model_dump() for z in body.zones]
    await res.db.users.update_one({"_id": user["_id"]}, {"$set": {"home_zones": zones}})
    return Response(status_code=204)


@router.post("/me/freeze", response_model=FreezeResponse, responses=errs(401, 403, 409, 422))
async def freeze(
    body: FreezeRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> FreezeResponse:
    s = res.settings
    if body.days > s.max_freeze_days:
        raise HTTPException(422, f"A freeze lasts at most {s.max_freeze_days} days")
    now = res.clock()
    fresh = await res.db.users.find_one({"_id": user["_id"]}) or user
    running = fresh.get("freeze_until")
    if body.days > 0:
        # Quota check first, counting the running freeze as ended now, so a refused request changes nothing.
        past = list(fresh.get("freeze_log", []))
        started = fresh.get("freeze_started_at")
        if running and started is not None and min(now, running) > started:
            past.append({"start": started, "end": min(now, running)})
        if not quota_ok(past, now, body.days, s.freeze_quota_days, s.freeze_window_days):
            raise HTTPException(409, f"At most {s.freeze_quota_days} frozen days in any {s.freeze_window_days} days")
    if running:  # end the running (or expired) freeze: forgive the paused time
        await settle_freeze(res.db, fresh, min(now, running))
    if body.days > 0:
        await rebase_for_freeze(res.db, user["_id"], now)  # decay that already happened stays
        until = now + body.days * DAY_MS
        await res.db.users.update_one(
            {"_id": user["_id"]}, {"$set": {"freeze_until": until, "freeze_started_at": now}}
        )
    after = await res.db.users.find_one({"_id": user["_id"]}) or fresh
    return FreezeResponse(**_freeze_status(res, after, now))


@router.delete("/me", status_code=204, responses=errs(401, 503))
async def delete_me(
    user: dict = Depends(auth.current_user_even_if_deleting), res: Resources = Depends(auth.get_res)
) -> Response:
    try:
        await delete_account(res, user["_id"])
    except (LockTimeout, *RETRYABLE, PyMongoError, RedisError):
        # Lock contention, a lock lost mid-way, Mongo or Redis trouble: the account stays in `deleting` (no uploads,
        # no claims, hidden from maps) and calling DELETE /me again resumes where it stopped.
        log.warning("delete_me_interrupted", exc_info=True)
        raise HTTPException(503, "Busy, retry", headers={"Retry-After": "5"}) from None
    return Response(status_code=204)


# ---------------------------------------------------------------- reports
@router.post("/reports", status_code=202, responses=errs(401, 403, 422, 429))
async def report(
    body: ReportRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> dict:
    retry = await hit_rate_limit(res, "reports", user["_id"], 20, 3600)
    if retry is not None:
        raise HTTPException(429, "Too many reports", headers={"Retry-After": str(retry)})
    await res.db.reports.insert_one(
        {
            "reporter_id": user["_id"],
            "kind": body.kind,
            "target_id": body.target_id,
            "reason": body.reason,
            "created_at": res.clock(),
            "expire_at": expiry(res, res.settings.reports_retention_days),  # TTL index purges it
            "state": "open",
        }
    )
    return {"status": "recorded"}
