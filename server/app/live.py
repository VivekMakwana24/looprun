"""WebSocket /v1/live: pushes cell ownership changes inside a bbox.

Auth: preferably a first message {"type":"auth","token":"..."} (tokens in URLs end up in proxy logs); the
`token` query parameter is still accepted. Worker -> Redis pub/sub (events.CHANNEL) -> every connected socket.
Each socket decides per viewer what to send and when: others see a change only after PUBLISH_DELAY_SECONDS,
the new owner sees it at once, and hidden cells never carry an owner.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from . import auth
from . import engine_adapter as eng
from .api import parse_bbox
from .cellview import build_views
from .events import CHANNEL
from .resources import Resources

log = logging.getLogger("looprun.live")
router = APIRouter(prefix="/v1")
MAX_PENDING = 5000


async def _live_user(res: Resources, token: str) -> dict | None:
    user_id = auth.decode_token(res, token) if token else None
    user = await res.db.users.find_one({"_id": user_id}) if user_id else None
    return None if user is None or user.get("deleting") else user


@router.websocket("/live")
async def live(ws: WebSocket) -> None:
    res: Resources = ws.app.state.res
    try:
        min_lng, min_lat, max_lng, max_lat = parse_bbox(ws.query_params.get("bbox", ""), res.settings.bbox_max_degrees)
    except ValueError:
        await ws.close(code=1008)
        return

    user = None
    token = ws.query_params.get("token", "")
    if token:
        user = await _live_user(res, token)
        if user is None:
            await ws.close(code=4401)
            return
        await _subscribe_and_run(ws, res, user, (min_lng, min_lat, max_lng, max_lat), accept_first=True)
        return
    # first-message auth: accept, then the client has a few seconds to send {"type":"auth","token":"..."}
    await ws.accept()
    try:
        msg = await asyncio.wait_for(ws.receive_json(), res.settings.ws_auth_timeout_seconds)
    except (TimeoutError, WebSocketDisconnect, ValueError, KeyError, RuntimeError):
        await _close(ws, 4401)
        return
    if not isinstance(msg, dict) or msg.get("type") != "auth" or not isinstance(msg.get("token"), str):
        await _close(ws, 4401)
        return
    user = await _live_user(res, msg["token"])
    if user is None:
        await _close(ws, 4401)
        return
    await _subscribe_and_run(ws, res, user, (min_lng, min_lat, max_lng, max_lat), accept_first=False)


async def _close(ws: WebSocket, code: int) -> None:
    with contextlib.suppress(Exception):
        await ws.close(code=code)


async def _subscribe_and_run(ws: WebSocket, res: Resources, user: dict, bbox: tuple, accept_first: bool) -> None:
    min_lng, min_lat, max_lng, max_lat = bbox
    user_id = user["_id"]
    pubsub = res.redis.pubsub()
    await pubsub.subscribe(CHANNEL)  # subscribe before accept/ready: nothing published afterwards is missed
    if accept_first:
        await ws.accept()

    send_lock = asyncio.Lock()
    pending: set[asyncio.Task] = set()

    async def deliver(evt: dict) -> None:
        cell = evt["cell"]
        if evt.get("new_owner") != user_id:
            wait = max(0, evt.get("reveal_at", 0) - res.clock()) / 1000
            if wait:
                await asyncio.sleep(wait)
        doc = await res.db.cells.find_one({"_id": cell})
        views = await build_views(res, [doc], user_id) if doc else []
        if views:
            v = views[0]
        else:
            lat, lng = eng.cell_centre(cell)
            v = {"lat": lat, "lng": lng, "owner": None, "mine": False}
        async with send_lock:
            await ws.send_json(
                {
                    "type": "cell_changed",
                    "cell": cell,
                    "lat": v["lat"],
                    "lng": v["lng"],
                    "owner": v["owner"],
                    "mine": v["mine"],
                }
            )

    async def pump() -> None:
        loop = asyncio.get_running_loop()
        next_check = loop.time() + res.settings.ws_recheck_seconds
        while True:
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if loop.time() >= next_check:  # the account may have been deleted (or the token invalidated)
                next_check = loop.time() + res.settings.ws_recheck_seconds
                if await res.db.users.find_one({"_id": user_id, "deleting": {"$ne": True}}) is None:
                    return
            if msg is None:
                await asyncio.sleep(0.01)
                continue
            try:
                evt = json.loads(msg["data"])
                if evt.get("user_deleted") == user_id:
                    return
                if "cell" not in evt:
                    continue
                lat, lng = eng.cell_centre(evt["cell"])
            except (ValueError, KeyError, TypeError, AttributeError):
                continue
            if not (min_lat <= lat <= max_lat and min_lng <= lng <= max_lng) or len(pending) >= MAX_PENDING:
                continue
            t = asyncio.create_task(deliver(evt))
            pending.add(t)
            t.add_done_callback(pending.discard)

    async def watch_client() -> None:
        try:
            while True:
                await ws.receive_text()
        except WebSocketDisconnect:
            return

    tasks = [asyncio.create_task(pump()), asyncio.create_task(watch_client())]
    try:
        done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        if tasks[0] in done:  # we ended it (user gone): tell the client
            await _close(ws, 4401)
    finally:
        for t in [*tasks, *pending]:
            t.cancel()
        with contextlib.suppress(Exception):
            await pubsub.unsubscribe(CHANNEL)
            await pubsub.aclose()
