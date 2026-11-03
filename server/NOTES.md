# Server notes

Run: `uvicorn app.main:create_app --factory`, worker: `celery -A app.worker:celery_app worker`.
Env (all `LOOPRUN_` prefixed; old unprefixed names accepted as fallbacks for a few): `LOOPRUN_MONGO_URL`,
`LOOPRUN_REDIS_URL`, `LOOPRUN_GOOGLE_CLIENT_ID` (the Web/server client id the Android app requests tokens for),
`LOOPRUN_JWT_SECRET` (required unless dev auth; at least 32 characters, otherwise the app refuses to start),
`LOOPRUN_DEV_AUTH`, `LOOPRUN_PUBLISH_DELAY_SECONDS` (1800), `LOOPRUN_PRIVACY_K` (3), `LOOPRUN_RUN_RATE_LIMIT` (30/h),
`LOOPRUN_MAX_FIXES`, ... see app/config.py. Nonsense values (halflife <= 0, lock TTL < 2 s, ...) fail at startup.
Tests: `LOOPRUN_TEST_ENGINE=fake|real` (default: real if installed, else tests/fake_engine.py).
`pytest server -q -o addopts="" -p no:warnings`; verifier findings are pinned in `tests/test_hardening.py`
(dispositions: docs/verification/S-fixes.md).

## Behaviour choices
- Only `app/engine_adapter.py` imports `looprun_engine`.
- Delayed publishing: cell docs hold `owner_id` (true) plus `public_owner_id` / `pending_*`; others see a change after
  the delay (GET /cells, WS and the leaderboard). The new owner sees their own cells at once.
- Cells and WS frames carry the cell centre `lat`/`lng` (engine `cell_centre`); a hidden cell is sent with `owner: null`.
- Leaderboard: counts only published ownership (3 aggregates over `cells`, cached 60 s as counts only); the viewer's
  own entry is added live. Processing does not touch the cache. It ignores home zones and K (it exposes counts only).
- Held runs: any hard flag and the soft flag `implausible_loop` (`engine_adapter.HOLD_SOFT_CODES`) give status
  `pending_review`, no cells, no cell_power, until reviewed (there is no review tool yet; that is manual in Mongo).
- Raw GPS lives in `run_fixes` (not in the run document). Accepted runs: deleted right after processing. Held, rejected,
  processing_error and (as a backstop) stuck `processing` runs: `expire_at` = 30 days (`LOOPRUN_FIXES_RETENTION_DAYS`),
  removed by a Mongo TTL index. Reports: `expire_at` 180 days, TTL index. (Mongo's TTL monitor runs about once a minute.)
- Processing is idempotent. Under the locks the claim is first *planned* (absolute new power per cell, stored in
  `run_claims`), then applied with guarded absolute writes, then the run is marked done. A redelivered task reuses the
  plan, so credit is never added twice. `apply_claim` is skipped when the credit is 0 (it would refresh grace for free).
- Errors: connection/timeouts (Mongo, Redis, sockets, lock timeouts) are `errors.RETRYABLE`: Celery `autoretry_for` with
  exponential backoff (max 6). On the last attempt, and for every other exception, the run becomes `rejected` with the
  hard flag `processing_error` (GPS kept for the review window only). A killed worker is covered by `acks_late`.
- Locks (`app/locks.py`): one lock per user and one per H3 resolution-5 parent region of the claimed cells. Order: user
  lock first, then regions sorted, so nobody deadlocks. Each lock has its own holder token, Lua compare-and-delete release,
  Lua compare-and-extend watchdog (TTL 30 s, extended every TTL/3 while the holder lives), `LockLost` if taken over. A dead
  worker blocks others for at most the TTL. Runs in different regions run in parallel; runs on one region serialise.
- Account deletion (`DELETE /me`, resumable): mark `deleting` (uploads and every other route give 403; workers skip claiming
  for deleting/missing users, re-checked inside the lock) -> publish `user_deleted` (open sockets close) -> user lock
  (waits for a claim in flight) -> region locks of everything the user holds (bounded wait, 5 attempts) -> hand each cell to
  the strongest remaining player by faded power or free it, delete cell_power -> runs, run_fixes, run_claims, reports they
  filed -> the user document LAST. Lock timeout -> 503 + Retry-After, the user stays `deleting`, the same token still works
  for DELETE /me only; repeating the call finishes. Reports about the user stay.
- Freeze: at most `max_freeze_days` (30) per freeze and 30 frozen days in any rolling 90 (409 otherwise, and a refused
  request changes nothing). Start: cell_power already past grace is rebased to faded(now) with `updated_at = now - grace`, so
  a freeze cannot bring decayed power back. End (days=0, a new freeze, or lazily when it has expired and the power is next
  read): `updated_at` shifts forward by the frozen time (engine/NOTES.md #10) and the interval goes into `freeze_log`.
- Request body cap: pure ASGI middleware counts streamed bytes (chunked too) -> 413. Numbers: NaN/Infinity and times
  beyond year 2100 -> 422 (never echoed back in the error body).
- Auth: dev names use `fullmatch`; Google verification allows 10 s clock skew and reuses a cached certificate fetch (1 h).
- WebSocket `/v1/live`: first message `{"type":"auth","token":"..."}` (preferred, keeps tokens out of proxy logs) or the
  `token` query parameter. The user must still exist (and not be `deleting`) on connect and is re-checked every 30 s.

## Questions / known limits
- `cells_claimed` = cells of the run the user owns after the run (includes ones already theirs); `cells_taken_from_others` =
  subset previously owned by someone else. Contract does not define it.
- POST /runs with an id belonging to another user returns 409. A repeat POST returns the current RunStatus.
- Display name = Google `given_name` (else `name`); it is public on the leaderboard.
- Play Integrity: token stored, verdict `unchecked` (the privacy policy must not claim it is checked).
- No sweeper for runs stuck in `processing` after a lost message (redelivery + the 30-day GPS TTL are the only cleanup).
- A run that fails after its plan was applied is marked rejected but keeps the credit already applied (rare; plan kept).
- `deploy/Caddyfile` is not in this lane: it still logs full URLs (WS `?token=`) and sets no `request_body max_size`.
- Tested with mongomock and fakeredis only; no real MongoDB/Redis suite yet (docs/verification/O1-C1-followups.md #3).
