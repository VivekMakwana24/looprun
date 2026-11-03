# Server notes

Run: `uvicorn app.main:create_app --factory`, worker: `celery -A app.worker:celery_app worker`.
Env (all `LOOPRUN_` prefixed; old unprefixed names accepted as fallbacks for a few): `LOOPRUN_MONGO_URL`,
`LOOPRUN_REDIS_URL`, `LOOPRUN_GOOGLE_CLIENT_ID`, `LOOPRUN_JWT_SECRET` (required unless dev auth), `LOOPRUN_DEV_AUTH`,
`LOOPRUN_PUBLISH_DELAY_SECONDS` (1800), `LOOPRUN_PRIVACY_K` (3), `LOOPRUN_RUN_RATE_LIMIT` (30/h), `LOOPRUN_MAX_FIXES`, ... see app/config.py.
Tests: `LOOPRUN_TEST_ENGINE=fake|real` (default: real if installed, else tests/fake_engine.py).

## Behaviour choices
- Only `app/engine_adapter.py` imports `looprun_engine`.
- Delayed publishing: cell docs hold `owner_id` (true) plus `public_owner_id` / `pending_*`; others see a change after the delay (GET /cells and WS). The new owner sees their own cells at once.
- WS frames are exactly `{type, cell, owner, mine}`; a hidden cell is sent with `owner: null`.
- Fixes are dropped from the run document after processing unless the run needs review (non-accepted or implausible_loop).
- Freeze: `freeze_started_at`/`freeze_until` on the user; when a freeze ends (days=0, a new freeze, or lazily when expired and the user's power is next read) `cell_power.updated_at` is shifted forward by the frozen time (engine/NOTES.md #10).
- Account deletion also deletes reports the user filed; reports about them stay.
- Processing takes a global Redis lock (`looprun:lock:claims`) so two workers cannot race on cell ownership. Simple, limits throughput; shard per H3 parent later.
- Leaderboard counts stored owners; ownership changed only by decay is materialised at the next claim on that cell (not by a job).

## Questions
- `cells_claimed` = cells of the run the user owns after the run (includes ones already theirs); `cells_taken_from_others` = subset previously owned by someone else. Contract does not define it.
- POST /runs with an id belonging to another user returns 409 (contract lists no code).
- Repeat POST returns the current RunStatus (not necessarily "processing").
- Request bodies above 8 MB (Content-Length) get 413; chunked bodies without a length are not capped here.
- Display name = Google `given_name` (else `name`); it is public on the leaderboard.
- Leaderboard shows true owners (not delayed) and ignores home zones: it only exposes counts.
- Play Integrity: token stored, verdict `unchecked`.
