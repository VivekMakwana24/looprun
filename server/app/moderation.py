"""Moderation CLI (docs/PHASE1_SPEC.md 8.3): `python -m app.moderation <command>` on the host, no HTTP surface.

    reports [--state open|hidden|dismissed|all] [--kind K] [--limit N]
    hide-comment <id> | unhide-comment <id>
    hide-name <user_id> | unhide-name <user_id>
    hide-run <run_id> | unhide-run <run_id>
    dismiss <report_id>

Every action is written to `moderation_log` (who, what, which reports). Hidden state is read at request time
everywhere, so the effect is visible through the API on the next request.
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import json
import sys
from datetime import UTC, datetime, timedelta
from typing import Any

from bson import ObjectId
from bson.errors import InvalidId

from .config import get_settings
from .events import invalidate_leaderboard
from .resources import Resources, build_resources

KINDS = ["run", "cell", "user", "comment", "run_card"]


class ModerationError(Exception):
    """A command that cannot be carried out (unknown target ...). Nothing was changed or logged."""


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="python -m app.moderation", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="command", required=True)
    r = sub.add_parser("reports", help="list reports with the snapshot of the target")
    r.add_argument("--state", default="open", choices=["open", "hidden", "dismissed", "all"])
    r.add_argument("--kind", choices=KINDS)
    r.add_argument("--limit", type=int, default=50)
    for name, what in (("comment", "comment id"), ("name", "user id"), ("run", "run id")):
        for verb in ("hide", "unhide"):
            c = sub.add_parser(f"{verb}-{name}", help=f"{verb} by {what}")
            c.add_argument("target", metavar=what.replace(" ", "_"))
    d = sub.add_parser("dismiss", help="mark a report dismissed (no action taken)")
    d.add_argument("report_id")
    return p


def _age(now_ms: int, then_ms: int) -> str:
    s = max(0, (now_ms - then_ms) // 1000)
    return f"{s // 86400}d{s % 86400 // 3600}h" if s >= 86400 else f"{s // 3600}h{s % 3600 // 60}m"


async def _log(
    res: Resources, admin: str, action: str, kind: str, target: str, report_ids: list[Any]
) -> None:
    now = res.clock()
    await res.db.moderation_log.insert_one(
        {
            "at": now,
            "admin": admin,
            "action": action,
            "target_kind": kind,
            "target_id": target,
            "report_ids": [str(r) for r in report_ids],
            "expire_at": datetime.fromtimestamp(now / 1000, UTC)
            + timedelta(days=res.settings.moderation_log_retention_days),
        }
    )


async def _resolve(res: Resources, kinds: list[str], target: str, state: str) -> list[Any]:
    """Open reports about this target move to `state`; returns their ids."""
    q = {"kind": {"$in": kinds}, "target_id": target, "state": "open"}
    ids = [r["_id"] async for r in res.db.reports.find(q, {"_id": 1})]
    if ids:
        await res.db.reports.update_many({"_id": {"$in": ids}}, {"$set": {"state": state, "resolved_at": res.clock()}})
    return ids


async def execute(res: Resources, argv: list[str], admin: str | None = None) -> list[str]:
    """Run one command; returns the output lines. Raises ModerationError when it cannot be done."""
    args = parser().parse_args(argv)
    admin = admin or getpass.getuser()
    cmd, db = args.command, res.db
    out: list[str] = []

    if cmd == "reports":
        q: dict = {} if args.state == "all" else {"state": args.state}
        if args.kind:
            q["kind"] = args.kind
        now = res.clock()
        async for r in db.reports.find(q).sort([("created_at", 1)]).limit(max(1, args.limit)):
            snap = json.dumps(r.get("snapshot"), ensure_ascii=False, default=str)
            out.append(
                f"{r['_id']}  {r.get('state', 'open')}  {r['kind']}  target={r['target_id']}"
                f"  owner={r.get('target_owner_id') or '-'}  reporter={r['reporter_id']}"
                f"  age={_age(now, r['created_at'])}\n    reason: {r['reason']}\n    snapshot: {snap}"
            )
        return out or ["no reports"]

    if cmd == "dismiss":
        try:
            rid = ObjectId(args.report_id)
        except (InvalidId, TypeError):
            raise ModerationError("not a report id") from None
        r = await db.reports.find_one({"_id": rid})
        if r is None:
            raise ModerationError("no such report")
        await db.reports.update_one({"_id": rid}, {"$set": {"state": "dismissed", "resolved_at": res.clock()}})
        await _log(res, admin, cmd, "report", str(rid), [rid])
        return [f"dismissed {rid}"]

    verb, _, name = cmd.partition("-")
    hide = verb == "hide"
    target = args.target
    if name == "comment":
        doc = await db.comments.find_one({"_id": target})
        if doc is None:
            raise ModerationError("no such comment")
        await db.comments.update_one({"_id": target}, {"$set": {"hidden": hide}})
        if hide:
            await db.notifications.delete_one({"_id": f"comment:{target}"})
        reports = await _resolve(res, ["comment"], target, "hidden") if hide else []
    elif name == "name":
        if await db.users.find_one({"_id": target}) is None:
            raise ModerationError("no such user")
        await db.users.update_one({"_id": target}, {"$set": {"name_hidden": hide}})
        await invalidate_leaderboard(res.redis, res.clock())
        reports = await _resolve(res, ["user"], target, "hidden") if hide else []
    else:
        if await db.runs.find_one({"_id": target}) is None:
            raise ModerationError("no such run")
        await db.runs.update_one({"_id": target}, {"$set": {"hidden": hide}})
        reports = await _resolve(res, ["run_card", "run"], target, "hidden") if hide else []
    await _log(res, admin, cmd, name, target, reports)
    return [f"{cmd} {target}: ok" + (f" ({len(reports)} report(s) marked hidden)" if reports else "")]


async def _run(argv: list[str]) -> int:
    settings = get_settings()
    if not settings.admin_enabled:
        print("the moderation CLI is disabled (LOOPRUN_ADMIN_ENABLED=false)", file=sys.stderr)
        return 2
    res = build_resources(settings)
    try:
        for line in await execute(res, argv):
            print(line)
        return 0
    except ModerationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    finally:
        await res.close()


def main(argv: list[str] | None = None) -> None:
    sys.exit(asyncio.run(_run(sys.argv[1:] if argv is None else argv)))


if __name__ == "__main__":
    main()
