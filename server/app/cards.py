"""Run cards (docs/PHASE1_SPEC.md 3 and 5): what a viewer may learn of an accepted run, assembled per page with a
constant number of queries (users, blocks, battle events, kudos, comments), never one query per card."""

from __future__ import annotations

from . import engine_adapter as eng
from . import social
from .resources import Resources

DAY_MS = 86_400_000


async def block_ids(res: Resources, viewer: str) -> set[str]:
    """Everybody blocked with the viewer in either direction (one query; the viewer has at most 500 blocks)."""
    q = {"$or": [{"blocker_id": viewer}, {"blocked_id": viewer}]}
    return {b["blocked_id"] if b["blocker_id"] == viewer else b["blocker_id"] async for b in res.db.blocks.find(q)}


def event_cutoff(res: Resources, now: int) -> int:
    """Battle events older than this are gone even before Mongo's TTL monitor has deleted them."""
    return now - res.settings.battle_retention_days * DAY_MS


def pace(distance_m: float | None, moving_seconds: int | None) -> float | None:
    if distance_m is None or moving_seconds is None or distance_m < 100:
        return None
    return moving_seconds / (distance_m / 1000)


async def count_kudos(res: Resources, run_ids: list[str], excluded: set[str]) -> dict[str, int]:
    # givers who are being deleted no longer count (comments are filtered the same way)
    givers = set(await res.db.kudos.distinct("user_id", {"run_id": {"$in": run_ids}})) - excluded
    gone = {u["_id"] async for u in res.db.users.find({"_id": {"$in": sorted(givers)}, "deleting": True}, {"_id": 1})}
    pipe = [
        {"$match": {"run_id": {"$in": run_ids}, "user_id": {"$nin": sorted(excluded | gone)}}},
        {"$group": {"_id": "$run_id", "n": {"$sum": 1}}},
    ]
    return {d["_id"]: d["n"] async for d in res.db.kudos.aggregate(pipe)}


async def comment_authors(res: Resources, run_ids: list[str], excluded: set[str]) -> dict[str, dict[str, int]]:
    """run -> {author -> number of visible comments}: not hidden, author not blocked with the viewer."""
    pipe = [
        {"$match": {"run_id": {"$in": run_ids}, "hidden": {"$ne": True}, "author_id": {"$nin": sorted(excluded)}}},
        {"$group": {"_id": {"r": "$run_id", "a": "$author_id"}, "n": {"$sum": 1}}},
    ]
    out: dict[str, dict[str, int]] = {}
    async for d in res.db.comments.aggregate(pipe):
        out.setdefault(d["_id"]["r"], {})[d["_id"]["a"]] = d["n"]
    return out


async def build_cards(res: Resources, viewer: str, runs: list[dict]) -> list[dict]:
    """RunCard dicts for `runs` (documents of the `runs` collection) as `viewer` may see them, in the given order.
    Cards whose owner is not a live user, or is blocked with the viewer, are left out (the viewer's own are kept)."""
    if not runs:
        return []
    now = res.clock()
    delay = res.settings.publish_delay_seconds * 1000
    run_ids = [r["_id"] for r in runs]
    excluded = await block_ids(res, viewer)
    kudos = await count_kudos(res, run_ids, excluded)
    mine = {k["run_id"] async for k in res.db.kudos.find({"_id": {"$in": [f"{r}:{viewer}" for r in run_ids]}})}
    authors = await comment_authors(res, run_ids, excluded)
    users = await social.live_users(
        res, {r["user_id"] for r in runs} | {a for per in authors.values() for a in per}
    )
    events: dict[str, list[dict]] = {}
    q = {"run_id": {"$in": run_ids}, "at": {"$gte": event_cutoff(res, now), "$lte": now - delay}}
    async for ev in res.db.battle_events.find(q):  # only events the map already shows
        events.setdefault(ev["run_id"], []).append(ev)
    flat = [ev for evs in events.values() for ev in evs]
    oks, victims = await social.name_ok_many(res, viewer, [(ev, ev.get("victim_id")) for ev in flat])
    named = {id(ev): ok for ev, ok in zip(flat, oks, strict=True)}

    cards: list[dict] = []
    for run in runs:
        owner_id = run["user_id"]
        owner = users.get(owner_id)
        if owner is None or (owner_id != viewer and owner_id in excluded):
            continue
        own = owner_id == viewer
        accepted = run["status"] == "accepted"
        evs = events.get(run["_id"], []) if accepted else []
        legacy = accepted and "claimed_cells" not in run
        zones = [(z["lat"], z["lng"], z["radius_m"]) for z in owner.get("home_zones", [])]

        def in_zone(cell: str, zones: list = zones) -> bool:
            return bool(zones) and eng.in_home_zone(cell, zones)

        if not accepted:
            claimed, taken_from, hidden = 0, {}, 0
        elif legacy:  # made before phase 1a: only the stored numbers, nobody is named
            claimed, taken_from, hidden = run.get("cells_claimed", 0), {}, run.get("cells_taken_from_others", 0)
        else:
            if own:
                claimed = run.get("cells_claimed", len(run["claimed_cells"]))
            else:  # home-zone cells are never counted for others
                claimed = sum(1 for c in run["claimed_cells"] if not in_zone(c))
                evs = [ev for ev in evs if not in_zone(ev["cell"])]
            taken_from, hidden = {}, 0
            for ev in evs:
                if named[id(ev)]:
                    taken_from[ev["victim_id"]] = taken_from.get(ev["victim_id"], 0) + 1
                else:
                    hidden += 1
        cards.append(
            {
                "id": run["_id"],
                "user": social.user_ref(owner, viewer),
                "started_at": run["started_at"],
                "distance_m": run.get("distance_m") if run["status"] != "processing" else None,
                "moving_seconds": run.get("moving_seconds") if run["status"] != "processing" else None,
                "pace_s_per_km": pace(run.get("distance_m"), run.get("moving_seconds"))
                if run["status"] != "processing"
                else None,
                "cells_claimed": claimed,
                "cells_taken": sum(taken_from.values()) + hidden,
                "taken_from": [
                    {"user": social.user_ref(victims[v], viewer), "cells": n} for v, n in taken_from.items()
                ],
                "taken_from_hidden": hidden,
                "loop_count": len(run.get("loops", [])),
                "kudos_count": kudos.get(run["_id"], 0),
                "kudos_by_me": run["_id"] in mine,
                "comment_count": sum(n for a, n in authors.get(run["_id"], {}).items() if a in users),
                "status": run["status"],
            }
        )
    return cards

