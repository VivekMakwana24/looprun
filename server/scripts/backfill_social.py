"""Run from a checkout: `cd server && python scripts/backfill_social.py` (same as `python -m app.backfill_social`)."""

import asyncio
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from app.backfill_social import main  # noqa: E402

if __name__ == "__main__":
    asyncio.run(main())
