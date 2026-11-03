"""What a viewer is allowed to see of a cell: delayed publishing, home zones and K-anonymity."""

from __future__ import annotations

from typing import Any

from . import engine_adapter as eng
from .resources import Resources

CHUNK = 4000


def public_owner(doc: dict, now: int, delay_ms: int) -> str | None:
    """The owner everybody else may see: a change is revealed delay_ms after it happened."""
    if doc.get("pending") and now >= doc.get("pending_at", 0) + delay_ms:
        return doc.get("pending_owner_id")
    return doc.get("public_owner_id")


def change_fields(doc: dict | None, new_owner: str, now: int, delay_ms: int) -> dict:
    """$set fields for an ownership change: first fold an already-revealed pending change into `public`."""
    public = public_owner(doc, now, delay_ms) if doc else None
    return {
        "owner_id": new_owner,
        "public_owner_id": public,
        "pending": True,
        "pending_owner_id": new_owner,
        "pending_at": now,
        "changed_at": now,
    }


async def _users_in_neighbourhoods(db: Any, cells: list[str], ring: int) -> dict[str, set[str]]:
    """For each given cell: the distinct users with power in its grid_disk(ring)."""
    neigh = {c: eng.grid_disk(c, ring) for c in cells}
    universe = sorted({n for ns in neigh.values() for n in ns})
    by_cell: dict[str, set[str]] = {}
    for i in range(0, len(universe), CHUNK):
        part = universe[i : i + CHUNK]
        async for d in db.cell_power.find({"cell": {"$in": part}}, {"cell": 1, "user_id": 1}):
            by_cell.setdefault(d["cell"], set()).add(d["user_id"])
    return {c: set().union(*(by_cell.get(n, set()) for n in ns)) for c, ns in neigh.items()}


def _cell(doc: dict, owner: dict | None, mine: bool, hidden: bool) -> dict:
    lat, lng = doc.get("lat"), doc.get("lng")
    if lat is None or lng is None:
        lat, lng = eng.cell_centre(doc["_id"])
    return {"id": doc["_id"], "lat": lat, "lng": lng, "owner": owner, "mine": mine, "hidden": hidden}


async def build_views(res: Resources, docs: list[dict], viewer_id: str | None) -> list[dict]:
    """Cell dicts {id, owner, mine, hidden} for the viewer. Cells nobody may see an owner for yet are left out."""
    s = res.settings
    now = res.clock()
    delay_ms = s.publish_delay_seconds * 1000
    chosen: list[tuple[dict, str]] = []
    for d in docs:
        if viewer_id and d.get("owner_id") == viewer_id:
            owner = viewer_id  # you always see your own cells at once
        else:
            owner = public_owner(d, now, delay_ms)
        if owner is not None:
            chosen.append((d, owner))
    if not chosen:
        return []

    owner_ids = sorted({o for _, o in chosen})
    users: dict[str, dict] = {}
    async for u in res.db.users.find({"_id": {"$in": owner_ids}}):
        users[u["_id"]] = u

    to_check = [d["_id"] for d, o in chosen if o != viewer_id and o in users]
    neighbours = await _users_in_neighbourhoods(res.db, to_check, s.privacy_ring) if to_check else {}

    out: list[dict] = []
    for d, owner in chosen:
        cid = d["_id"]
        user = users.get(owner)
        if user is None:  # owner vanished (should not happen); never show a ghost
            continue
        if owner == viewer_id:
            out.append(_cell(d, {"id": owner, "name": user["name"]}, True, False))
            continue
        zones = [(z["lat"], z["lng"], z["radius_m"]) for z in user.get("home_zones", [])]
        hidden = eng.in_home_zone(cid, zones) or len(neighbours.get(cid, ())) < s.privacy_min_users
        out.append(_cell(d, None if hidden else {"id": owner, "name": user["name"]}, False, hidden))
    return out
