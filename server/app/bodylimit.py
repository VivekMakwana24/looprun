"""Pure ASGI request-body cap that also covers chunked uploads (no Content-Length)."""

from __future__ import annotations

import json


class BodyLimitMiddleware:
    def __init__(self, app, max_bytes: int):
        self.app, self.max_bytes = app, max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False
        rejected = False

        async def reject():
            nonlocal rejected, started
            if rejected or started:
                return
            rejected = True
            body = json.dumps({"detail": "Payload too large"}).encode()
            await send(
                {
                    "type": "http.response.start",
                    "status": 413,
                    "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())],
                }
            )
            await send({"type": "http.response.body", "body": body})

        for k, v in scope["headers"]:
            if k == b"content-length" and v.isdigit() and int(v) > self.max_bytes:
                await reject()
                return

        total = 0

        async def limited_receive():
            nonlocal total
            if rejected:
                return {"type": "http.disconnect"}
            msg = await receive()
            if msg["type"] == "http.request":
                total += len(msg.get("body", b""))
                if total > self.max_bytes:
                    await reject()
                    return {"type": "http.disconnect"}
            return msg

        async def guarded_send(msg):
            nonlocal started
            if rejected:
                return  # the 413 is already out; swallow whatever the app tries to say next
            if msg["type"] == "http.response.start":
                started = True
            await send(msg)

        await self.app(scope, limited_receive, guarded_send)
