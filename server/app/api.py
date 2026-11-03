"""REST routes under /v1 (docs/CONTRACT.openapi.yaml)."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pymongo.errors import DuplicateKeyError

from . import auth
from .cellview import build_views
from .errors import LockTimeout
from .events import iso_week, leaderboard_key
from .freeze import quota_ok, rebase_for_freeze, settle_freeze
from .models import (
    CellsResponse,
    FreezeRequest,
    FreezeResponse,
    GoogleAuthRequest,
    HomeZonesRequest,
    LeaderboardResponse,
    ReportRequest,
    RunStatus,
    RunUpload,
    Session,
    UserRef,
)
from .processing import delete_account, expiry
from .resources import Resources
from .worker import enqueue_run

log = logging.getLogger("looprun.api")
router = APIRouter(prefix="/v1")

DAY_MS = 86_400_000


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


async def hit_rate_limit(res: Resources, scope: str, user_id: str, limit: int, window_s: int) -> int | None:
    """Fixed-window counter in Redis. Returns None when allowed, else seconds until the window ends."""
    bucket = (res.clock() // 1000) // window_s
    key = f"looprun:rl:{scope}:{user_id}:{bucket}"
    n = await res.redis.incr(key)
    if n == 1:
        await res.redis.expire(key, window_s)
    if n > limit:
        return max(1, int((bucket + 1) * window_s - res.clock() // 1000))
    return None


# ---------------------------------------------------------------- auth
@router.post("/auth/google", response_model=Session)
async def auth_google(body: GoogleAuthRequest, request: Request, res: Resources = Depends(auth.get_res)) -> Session:
    subject, name = await auth.identify(res, request.app.state.google_verifier, body.id_token)
    user = await auth.upsert_user(res, subject, name)
    return Session(access_token=auth.create_token(res, user["_id"]), user=UserRef(id=user["_id"], name=user["name"]))


# ---------------------------------------------------------------- runs
@router.post("/runs", status_code=202, response_model=RunStatus)
async def upload_run(
    body: RunUpload, response: Response, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> RunStatus:
    s = res.settings
    run_id = str(body.id)
    existing = await res.db.runs.find_one({"_id": run_id})
    if existing is not None:
        if existing["user_id"] != user["_id"]:
            raise HTTPException(409, "Run id already used")
        return run_status(existing)  # idempotent: same id -> same run, no new work
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
        if again is None or again["user_id"] != user["_id"]:
            raise HTTPException(409, "Run id already used") from None
        return run_status(again)
    try:
        await res.db.run_fixes.insert_one(
            {
                "_id": run_id,
                "user_id": user["_id"],
                "fixes": [[f.lat, f.lng, f.t, f.acc, f.mock] for f in body.fixes],
                # even a run stuck in `processing` must not keep raw GPS forever
                "expire_at": expiry(res, s.fixes_retention_days),
            }
        )
        await asyncio.to_thread(enqueue_run, run_id)
    except Exception:
        log.exception("enqueue_failed", extra={"run_id": run_id})
        await res.db.run_fixes.delete_one({"_id": run_id})
        await res.db.runs.delete_one({"_id": run_id})  # let the client retry with the same id
        raise HTTPException(503, "Queue unavailable") from None
    current = await res.db.runs.find_one({"_id": run_id})
    return run_status(current or doc)


@router.get("/runs/{run_id}", response_model=RunStatus)
async def get_run(
    run_id: UUID, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> RunStatus:
    doc = await res.db.runs.find_one({"_id": str(run_id), "user_id": user["_id"]})
    if doc is None:
        raise HTTPException(404, "Unknown run")
    return run_status(doc)


# ---------------------------------------------------------------- map
@router.get("/cells", response_model=CellsResponse)
async def get_cells(
    bbox: str = Query(...), user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> CellsResponse:
    s = res.settings
    try:
        min_lng, min_lat, max_lng, max_lat = parse_bbox(bbox, s.bbox_max_degrees)
    except ValueError as e:
        raise HTTPException(422, str(e)) from None
    q = {"lat": {"$gte": min_lat, "$lte": max_lat}, "lng": {"$gte": min_lng, "$lte": max_lng}}
    docs = [d async for d in res.db.cells.find(q).limit(s.cells_max_results)]
    return CellsResponse(cells=await build_views(res, docs, user["_id"]))


async def _public_counts(res: Resources, now: int) -> dict[str, int]:
    """Cells per user counting only ownership that is already published (same delay as GET /cells for others)."""
    cutoff = now - res.settings.publish_delay_seconds * 1000
    counts: dict[str, int] = {}

    async def add(match: dict, field: str) -> None:
        pipeline = [{"$match": match}, {"$group": {"_id": f"${field}", "n": {"$sum": 1}}}]
        async for r in res.db.cells.aggregate(pipeline):
            if r["_id"] is not None:
                counts[r["_id"]] = counts.get(r["_id"], 0) + r["n"]

    await add({"pending": True, "pending_at": {"$lte": cutoff}}, "pending_owner_id")  # change already revealed
    await add({"pending": {"$ne": True}, "public_owner_id": {"$ne": None}}, "public_owner_id")  # nothing pending
    await add({"pending": True, "pending_at": {"$gt": cutoff}, "public_owner_id": {"$ne": None}}, "public_owner_id")
    return counts


@router.get("/leaderboard/weekly", response_model=LeaderboardResponse)
async def leaderboard(
    user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> LeaderboardResponse:
    s = res.settings
    now = res.clock()
    week = iso_week(now)
    key = leaderboard_key(week)
    counts: dict[str, int] | None = None
    if s.leaderboard_cache_seconds > 0:
        cached = await res.redis.get(key)
        if cached:
            counts = json.loads(cached)
    if counts is None:
        counts = await _public_counts(res, now)
        if s.leaderboard_cache_seconds > 0:
            await res.redis.set(key, json.dumps(counts), ex=s.leaderboard_cache_seconds)
    # Everybody sees only published ownership; the viewer additionally sees their own entry at once.
    own = await res.db.cells.count_documents({"owner_id": user["_id"]})
    counts = {**counts, user["_id"]: own}
    counts = {uid: n for uid, n in counts.items() if n > 0}
    users = {u["_id"]: u async for u in res.db.users.find({"_id": {"$in": sorted(counts)}})}
    rows = sorted(
        ((n, users[uid]["name"], uid) for uid, n in counts.items() if uid in users), key=lambda r: (-r[0], r[1], r[2])
    )
    entries = [
        {"rank": i + 1, "user": {"id": uid, "name": name}, "cells": n}
        for i, (n, name, uid) in enumerate(rows[: s.leaderboard_size])
    ]
    return LeaderboardResponse(week=week, entries=entries)


# ---------------------------------------------------------------- me
@router.put("/me/home-zones", status_code=204)
async def put_home_zones(
    body: HomeZonesRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> Response:
    zones = [z.model_dump() for z in body.zones]
    await res.db.users.update_one({"_id": user["_id"]}, {"$set": {"home_zones": zones}})
    return Response(status_code=204)


@router.post("/me/freeze", response_model=FreezeResponse)
async def freeze(
    body: FreezeRequest, user: dict = Depends(auth.current_user), res: Resources = Depends(auth.get_res)
) -> FreezeResponse:
    s = res.settings
    if body.days > s.max_freeze_days:
        raise HTTPException(422, f"A freeze lasts at most {s.max_freeze_days} days")
    now = res.clock()
    fresh = await res.db.users.find_one({"_id": user["_id"]}) or user
    if fresh.get("freeze_until"):  # end the running (or expired) freeze first: forgive the paused time
        await settle_freeze(res.db, fresh, min(now, fresh["freeze_until"]))
    if body.days == 0:
        return FreezeResponse(freeze_until=None)
    if not quota_ok(fresh.get("freeze_log", []), now, body.days, s.freeze_quota_days, s.freeze_window_days):
        raise HTTPException(409, f"At most {s.freeze_quota_days} frozen days in any {s.freeze_window_days} days")
    await rebase_for_freeze(res.db, user["_id"], now)  # decay that already happened stays
    until = now + body.days * DAY_MS
    await res.db.users.update_one({"_id": user["_id"]}, {"$set": {"freeze_until": until, "freeze_started_at": now}})
    return FreezeResponse(freeze_until=until)


@router.delete("/me", status_code=204)
async def delete_me(
    user: dict = Depends(auth.current_user_even_if_deleting), res: Resources = Depends(auth.get_res)
) -> Response:
    try:
        await delete_account(res, user["_id"])
    except LockTimeout:
        # The account stays in `deleting` (no uploads, no claims); calling DELETE /me again finishes the job.
        raise HTTPException(503, "Busy, retry", headers={"Retry-After": "5"}) from None
    return Response(status_code=204)


# ---------------------------------------------------------------- reports
@router.post("/reports", status_code=202)
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
            "state": "open",
        }
    )
    return {"status": "recorded"}
