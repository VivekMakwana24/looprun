# O1-C1 follow-ups (work owned by other lanes, or deliberately deferred)

Written by the DevOps/Compliance builder in response to `docs/verification/O1-C1.md`.

## Server lane
1. **Purge raw GPS of runs held for review** (policy proposal: after 90 days). Add a TTL index on a purge-date field, or a periodic Celery task that `$unset`s `fixes` (finding 5). The privacy policy says "proposal, not yet implemented" until this exists.
2. **Purge old reports** (proposal: 12 months), same mechanism.
3. **Real-service integration tests.** Server tests use fakeredis/mongomock; add a small suite that honours `LOOPRUN_MONGO_URL` / `LOOPRUN_REDIS_URL` (unique indexes, Celery against real Redis). When it exists, re-add the `redis` and `mongo` service containers to `ci.yml` python job (removed because nothing used them) (finding 14).
4. **Display name**: decide if the stored name should be Google's `given_name` (current) or a user-chosen name; it is shown to other players (finding 7).
5. Server-side minimum for `LOOPRUN_JWT_SECRET` (reject short or `CHANGE_ME` values), as defence in depth (finding 13).

## Mobile lane
6. **Disclosure screen text**: make it match `docs/compliance/location-disclosure.md`, section "In-app screen text (must match code)": map and home-zone reads, home-zone storage, sharing/tile-provider paragraph, and a tappable Privacy Policy link (findings 3, 11).
7. **Notification Stop action** (optional; documents currently say there is none) (finding 9).
8. **Report a run or cell** screen and **WebSocket /v1/live** client; until then they are excluded from the listing and tester guide (finding 10).
9. **Profile toast** "Runs inside it stay hidden from other players" should read "Cells inside it never show your name" (finding 24).
10. **Delete-account dialog** text: add that cells pass to the strongest remaining player (finding 4).
11. Production **tile provider** decision and `MAP_STYLE_URL` repository variable (finding 8).
12. Add Firebase Crashlytics / Play Integrity only together with updates to the privacy policy and Data safety answers (finding 6).

## DevOps / owner decisions still open
13. Pin GitHub Actions by SHA and Flutter by version; add a CI gate to `release-android.yml` (finding 21).
14. Automatic rollback after failed deploy health check (finding 21).
15. Mongo `wiredTigerCacheSizeGB` cap for small hosts; Caddy wait for healthy api; hard-coded `/opt/looprun/.env` path in prod compose (finding 20).
16. Offsite backups (RUNBOOK section 5).
