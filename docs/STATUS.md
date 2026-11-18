# Status (2026-11-17)

CI green on main after the app redesign (all four jobs: Python ruff+pytest, real MongoDB/Redis integration, Flutter
analyze/test/debug APK + manifest check, Docker build). Report: docs/verification/M-redesign.md.

| Lane | State |
| --- | --- |
| Engine | Accepted. Cell boundary helper for D10. |
| Server | Accepted after fix waves 1 and 2. D10: cell boundary, own-cell strength, leaderboard `me`, `GET /me` with freeze quota. |
| Mobile | Phase 2 accepted with fixes. "Night Track" redesign done (4 themes, lanes, hexagon map, live run loop picture, result bib, board, profile); most deferred review items F3-F26 fixed. Compiles and passes tests in CI; **not yet run on a device**. |
| DevOps/Compliance | Fixes applied; disclosure doc and tester guide updated for the redesign. Re-verification pending. |
| Letter assistant | Held. |

Next: install the debug APK on two phones (Gate 1: 30-minute screen-off run; Google sign-in with the debug SHA-1;
map rendering of the hexagon layers and theme switch), then an independent review of the redesign.

Open follow-ups: docs/verification/M-redesign.md "Not verified" and "Gaps", O1-C1 follow-ups, commit pubspec.lock,
stale `deleting` accounts sweeper, map tile provider decision.
User-side: Play account type, 12 testers, OAuth client IDs (web client set; Android client with the release SHA-1
still needed for release builds), AWS Lightsail, signing keystore + GitHub secrets, privacy policy hosting.

## Mobile phase 1a (2026-11-18)

Feed, run detail with comments and kudos, public profiles, follow/block/report, followers/following, search, rivals,
battles, "take it back" sheet, inbox with bell, run history and rename are written against the phase 1a contract.
Navigation: BOARD hub (FEED / RANKS / RIVALS), see mobile/NOTES.md. Not yet run on a device; checklist in
docs/verification/phase1-device-checklist.md.
