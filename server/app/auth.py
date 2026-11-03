"""Session tokens (JWT HS256), Google ID token verification and the dev login."""

from __future__ import annotations

import asyncio
import logging
import re
import time
import uuid
from collections.abc import Callable
from typing import Any

import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pymongo.errors import DuplicateKeyError

from .resources import Resources

log = logging.getLogger("looprun.auth")
_bearer = HTTPBearer(auto_error=False)
DEV_NAME = re.compile(r"^[A-Za-z0-9_.-]{1,40}$")


def create_token(res: Resources, user_id: str) -> str:
    now = int(time.time())  # real time: PyJWT checks exp against the real clock
    s = res.settings
    return jwt.encode({"sub": user_id, "iat": now, "exp": now + s.jwt_ttl_seconds}, s.jwt_secret, algorithm="HS256")


def decode_token(res: Resources, token: str) -> str | None:
    try:
        claims = jwt.decode(
            token,
            res.settings.jwt_secret,
            algorithms=["HS256"],
            options={"require": ["exp", "sub"], "verify_iat": False},
            leeway=0,
        )
    except jwt.PyJWTError:
        return None
    sub = claims.get("sub")
    return sub if isinstance(sub, str) else None


def google_verify(token: str, client_id: str) -> dict:
    """Verify a Google ID token (signature, expiry, audience). Blocking: call in a thread."""
    from google.auth.transport import requests as g_requests  # noqa: PLC0415
    from google.oauth2 import id_token as g_id_token  # noqa: PLC0415

    return g_id_token.verify_oauth2_token(token, g_requests.Request(), client_id)


GoogleVerifier = Callable[[str, str], dict]


async def identify(res: Resources, verifier: GoogleVerifier, id_token: str) -> tuple[str, str]:
    """Returns (subject key, display name) or raises HTTPException 401/503."""
    s = res.settings
    if s.dev_auth and id_token.startswith("dev:"):
        name = id_token[4:]
        if not DEV_NAME.match(name):
            raise HTTPException(401, "Invalid token")
        return f"dev:{name}", name
    if not s.google_client_id:
        raise HTTPException(
            401 if s.dev_auth else 503, "Invalid token" if s.dev_auth else "Google sign-in is not configured"
        )
    try:
        claims = await asyncio.to_thread(verifier, id_token, s.google_client_id)
    except Exception:  # noqa: BLE001 - google-auth raises ValueError and transport errors
        raise HTTPException(401, "Invalid token") from None
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(401, "Invalid token")
    name = (claims.get("given_name") or claims.get("name") or "Runner")[:40]
    return f"google:{sub}", name


async def upsert_user(res: Resources, subject: str, name: str) -> dict:
    users = res.db.users
    user = await users.find_one({"google_sub": subject})
    if user is None:
        doc = {
            "_id": uuid.uuid4().hex,
            "google_sub": subject,
            "name": name,
            "created_at": res.clock(),
            "home_zones": [],
            "freeze_until": None,
        }
        try:
            await users.insert_one(doc)
            return doc
        except DuplicateKeyError:
            user = await users.find_one({"google_sub": subject})
    return user


def get_res(request: Request) -> Resources:
    return request.app.state.res


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer), res: Resources = Depends(get_res)
) -> dict:
    if creds is None:
        raise HTTPException(401, "Missing token", headers={"WWW-Authenticate": "Bearer"})
    user_id = decode_token(res, creds.credentials)
    user: Any = await res.db.users.find_one({"_id": user_id}) if user_id else None
    if user is None:
        raise HTTPException(401, "Invalid token", headers={"WWW-Authenticate": "Bearer"})
    return user
