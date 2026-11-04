# Server notes

Run: `uvicorn app.main:create_app --factory`, worker: `celery -A app.worker:celery_app worker`.
Env (all `LOOPRUN_` prefixed; old unprefixed names accepted as fallbacks for a few): `LOOPRUN_MONGO_URL`,
`LOOPRUN_REDIS_URL`, `LOOPRUN_GOOGLE_CLIENT_ID` (the Web/server client id the Android app requests tokens for),
`LOOPRUN_JWT_SECRET` (required unless dev auth; at least 32 characters, otherwise the app refuses to start),
`LOOPRUN_DEV_AUTH`, `LOOPRUN_PUBLISH_DELAY_SECONDS` (1800), `LOOPRUN_PRIVACY_K` (3), `LOOPRUN_RUN_RATE_LIMIT` (30/h),
`LOOPRUN_MAX_FIXES`, ... see app/config.py. Nonsense values (halflife <= 0, lock TTL < 2 s, ...) fail at startup.
Worker + sweeper: `celery -A app.worker:celery_app worker -B` (or a separate `celery -A app.worker:celery_app beat`).
Tests: `LOOPRUN_TEST_ENGINE=fake|real` (default: real if installed, else tests/fake_engine.py).
`pytest server -q -o addopts="" -p no:warnings`; verifier findings are pinned in `tests/test_hardening.py` (docs/verification/S-fixes.md) and
`tests/test_hardening2.py` (second pass, docs/verification/S-fixes2.md).

## Behaviour choices
- Only `app/engine_adapter.py` imports `looprun_engine`.
- Delayed publishing: cell docs hold `owner_id` (true) plus `public_owner_id` / `pending_*`; others see a change after
  the delay (GET /cells, WS and the leaderboard). The new owner sees their own cells at once.
- Cells and WS frames carry the cell centre `lat`/`lng` (engine `cell_centre`); a hidden cell is sent with `owner: null`.
- Leaderboard: counts exactly what a stranger sees on GET /cells with a name (published ownership, owner not `deleting`,
  not in a home zone, K-anonymity satisfied; it runs `build_views(viewer=None)` over all cells in batches of 5000 and is
  cached 60 s as counts only); users whose cells are all hidden are not listed. The viewer's own entry is added live.
  Processing does not touch the cache.
- A `deleting` account is invisible at once: its cells count as unowned in GET /cells, WS frames and the leaderboard
  until DELETE /me finishes and reassigns them.
- Held runs: any hard flag and the soft flag `implausible_loop` (`engine_adapter.HOLD_SOFT_CODES`) give status
  `pending_review`, no cells, no cell_power, until reviewed (there is no review tool yet; that is manual in Mongo).
- Raw GPS lives in `run_fixes` (not in the run document). Accepted runs: deleted right after processing. Held, rejected,
  processing_error and (as a backstop) stuck `processing` runs: `expire_at` = 30 days (`LOOPRUN_FIXES_RETENTION_DAYS`),
  removed by a Mongo TTL index. Reports: `expire_at` 180 days, TTL index. (Mongo's TTL monitor runs about once a minute.)
- Processing is idempotent. Under the locks the claim is first *planned* (absolute new power per cell, stored in
  `run_claims`), then applied with guarded absolute writes, then the run is marked done and the plan DELETED, all inside
  the lock (a second worker holding the same run re-reads its status under the lock and stops). Once applied, the plan
  is compacted to counts + the changes to publish (no per-cell outcomes). A redelivered task reuses the plan, so credit
  is never added twice. `run_claims` also has a TTL (`expire_at`) as a backstop. `apply_claim` is skipped when the
  credit is 0 (it would refresh grace for free).
- No run stays `processing`: POST /runs checks the user again after the insert (a deleting/deleted account gets
  403/401 and the run and fixes are removed); a repeated upload of a run that is still `processing` after
  `run_reenqueue_after_seconds` (30 s) re-stores missing fixes and enqueues it again; the sweeper
  (`looprun.sweep_stuck_runs`, celery beat every `sweep_interval_seconds` = 60) re-enqueues runs `processing` for
  more than `stuck_run_seconds` (300 s). Enqueueing is idempotent per run id. Not tied to /healthz.
- Errors: connection/timeouts (Mongo, Redis, sockets, lock timeouts) are `errors.RETRYABLE`: Celery `autoretry_for` with
  exponential backoff (max 6). On the last attempt, and for every other exception, the run becomes `rejected` with the
  hard flag `processing_error` (GPS kept for the review window only). A killed worker is covered by `acks_late`.
- Locks (`app/locks.py`): one lock per user and one per H3 resolution-5 parent region of the claimed cells. Order: user
  lock first, then regions sorted, so nobody deadlocks. Each lock has its own holder token, Lua compare-and-delete release,
  Lua compare-and-extend watchdog (TTL 30 s, extended every TTL/3 while the holder lives; it starts with the FIRST
  lock, and if any lock is lost the whole set fails with `LockLost` and releases what it holds), `LockLost` if taken over. A dead
  worker blocks others for at most the TTL. Runs in different regions run in parallel; runs on one region serialise.
- Account deletion (`DELETE /me`, resumable): mark `deleting` (uploads and every other route give 403; workers skip claiming
  for deleting/missing users, re-checked inside the lock) -> publish `user_deleted` (open sockets close) -> user lock
  (waits for a claim in flight) -> region locks of everything the user holds (bounded wait, 5 attempts) -> hand each cell to
  the strongest remaining player by faded power or free it, delete cell_power -> runs, run_fixes, run_claims, reports they
  filed -> claim plans of other users' in-flight runs are scrubbed of the id -> the user document LAST -> Redis keys that
  contain the id (rate limits, socket registry) and the cached leaderboard are removed. Lock timeout, LockLost, Mongo
  or Redis errors -> 503 + Retry-After, the user stays `deleting`, the same token still works for DELETE /me only;
  repeating the call finishes. Reports about the user stay (they hold the target id, not a user id). A test scans every
  collection and every Redis key for the deleted id.
- Freeze: at most `max_freeze_days` (30) per freeze and 30 frozen days in any rolling 90 (409 otherwise, and a refused
  request changes nothing). Start: cell_power already past grace is rebased to faded(now) with `updated_at = now - grace`, so
  a freeze cannot bring decayed power back. Every cell_power write of the freeze helpers is a compare-and-set on
  (power, updated_at) and retries from the new row, so it cannot overwrite a claim applied in between. End (days=0, a new freeze, or lazily when it has expired and the power is next
  read): `updated_at` shifts forward by the frozen time (engine/NOTES.md #10) and the interval goes into `freeze_log`.
- Request body cap: pure ASGI middleware counts streamed bytes (chunked too) -> 413. Numbers: NaN/Infinity and times
  beyond year 2100 -> 422 (never echoed back in the error body).
- Auth: dev names use `fullmatch`; Google verification allows 10 s clock skew and reuses a cached certificate fetch (1 h).
- WebSocket `/v1/live`: first message `{"type":"auth","token":"..."}` (preferred, keeps tokens out of proxy logs) or the
  `token` query parameter. The user must still exist (and not be `deleting`) on connect and is re-checked every 30 s.
  Handshake failures (bad bbox, bad query token, over the cap) are HTTP 403 because the server closes before accepting;
  first-message failures close with 4401, a 6th socket of a user with 4429. Cap: 5 sockets per user
  (`ws_max_sockets_per_user`), counted in Redis (sorted set `looprun:ws:<user>`, heartbeat every recheck, entries of
  crashed processes expire after 3 missed heartbeats).
- GET /cells is rate limited per user in Redis (`cells_rate_limit` = 120 per `cells_rate_window_seconds` = 60,
  env `LOOPRUN_CELLS_RATE_LIMIT`) -> 429 + Retry-After.
- `app.openapi()` lists the same status codes per route as docs/CONTRACT.openapi.yaml (`responses=` on the routes;
  a test compares them).

## Questions / known limits
- `cells_claimed` = cells of the run the user owns after the run (includes ones already theirs); `cells_taken_from_others` =
  subset previously owned by someone else. Contract does not define it.
- POST /runs with an id belonging to another user returns 409. A repeat POST returns the current RunStatus.
- Display name = Google `given_name` (else `name`); it is public on the leaderboard.
- Play Integrity: token stored, verdict `unchecked` (the privacy policy must not claim it is checked).
- A run that fails after its plan was applied is marked rejected but keeps the credit already applied (rare; plan kept).
- `deploy/Caddyfile` is not in this lane: it still logs full URLs (WS `?token=`) and sets no `request_body max_size`.
- Tested with mongomock and fakeredis only; no real MongoDB/Redis suite yet (docs/verification/O1-C1-followups.md #3).

## Known scale-only limits (deliberately not done in the second fix wave)
- Leaderboard: aggregates by walking every cell document (batches of 5000) once per cache miss; fine for thousands of
  cells, needs a materialised per-user count for millions.
- `_user_regions` / `_reassign_cells` put all cells of the user in one `$in` list (16 MB document limit at roughly 600k
  cells): chunk it if a single user can hold that many.
- One sleeping asyncio task per event per socket (delayed publishing); a Redis stream/zset of due events would scale better.
- Stale `deleting` accounts whose client never retries DELETE /me are not finished by a job (they are invisible and
  cannot upload; a sweeper that calls delete_account for `deleting` users older than N hours would close this).
- LockSet still relies on callers passing keys in sorted order (both callers do); no defensive sort inside.
- Eager Celery re-raises `Retry` from `enqueue_run`, so real retry timing is only covered by a manual retry loop.
- A run that fails after its plan was applied is `rejected` but keeps the credit already applied (rare).
- Google certificate cache (1 h) means a token signed by a freshly rotated key fails until the cache expires.
