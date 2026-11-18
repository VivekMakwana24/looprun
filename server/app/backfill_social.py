"""One-off, idempotent migration for Phase 1a (docs/PHASE1_SPEC.md 0.6): users get `name_lower` and
`name_hidden=false`, then every index is created. Safe to run any number of times, before or after the deploy.

    python -m app.backfill_social            (inside the api container; also server/scripts/backfill_social.py)
"""

from __future__ import annotations

import asyncio
from typing import Any

from .config import get_settings
from .profanity import name_key
from .resources import build_resources, ensure_indexes


async def backfill(db: Any) -> int:
    """Returns how many user documents were changed."""
    changed = 0
    async for u in db.users.find({"$or": [{"name_lower": {"$exists": False}}, {"name_hidden": {"$exists": False}}]}):
        fields: dict[str, Any] = {}
        if "name_lower" not in u:
            fields["name_lower"] = name_key(u["name"])
        if "name_hidden" not in u:
            fields["name_hidden"] = False
        await db.users.update_one({"_id": u["_id"]}, {"$set": fields})
        changed += 1
    await ensure_indexes(db)
    return changed


async def main() -> None:
    res = build_resources(get_settings())
    try:
        n = await backfill(res.db)
        print(f"backfill_social: {n} users updated, indexes ensured")
    finally:
        await res.close()


if __name__ == "__main__":
    asyncio.run(main())
