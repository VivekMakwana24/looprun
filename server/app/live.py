"""WebSocket /v1/live: pushes cell ownership changes inside a bbox.

Worker -> Redis pub/sub (events.CHANNEL) -> every connected socket. Each socket decides per viewer what to
send and when: others see a change only after PUBLISH_DELAY_SECONDS, the new owner sees it at once, and
hidden cells never carry an owner.
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

log = logging.getLogger("looprun.live")
router = APIRouter(prefix="/v1")
MAX_PENDING = 5000


@router.websocket("/live")
async def live(ws: WebSocket) -> None:
    res = ws.app.state.res
    token = ws.query_params.get("token", "")
    user_id = auth.decode_token(res, token) if token else None
    user = await res.db.users.find_one({"_id": user_id}) if user_id else None
    if user is None:
        await ws.close(code=4401)
        return
    try:
        min_lng, min_lat, max_lng, max_lat = parse_bbox(ws.query_params.get("bbox", ""), res.settings.bbox_max_degrees)
    except ValueError:
        await ws.close(code=1008)
        return

    pubsub = res.redis.pubsub()
    await pubsub.subscribe(CHANNEL)  # subscribe before accept: nothing published after the handshake is missed
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
        v = views[0] if views else {"owner": None, "mine": False}
        async with send_lock:
            await ws.send_json({"type": "cell_changed", "cell": cell, "owner": v["owner"], "mine": v["mine"]})

    async def pump() -> None:
        while True:
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if msg is None:
                await asyncio.sleep(0.01)
                continue
            try:
                evt = json.loads(msg["data"])
                lat, lng = eng.cell_centre(evt["cell"])
            except (ValueError, KeyError, TypeError):
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
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for t in [*tasks, *pending]:
            t.cancel()
        with contextlib.suppress(Exception):
            await pubsub.unsubscribe(CHANNEL)
            await pubsub.aclose()
