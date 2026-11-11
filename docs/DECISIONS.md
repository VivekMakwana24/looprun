# Decisions log

| # | Date | Decision | Why | Source |
| --- | --- | --- | --- | --- |
| D1 | 2026-11-03 | Monorepo `looprun` with `engine/`, `server/`, `mobile/`, `docs/` (superseded by D9) | One place for contract, CI and board; folders are owned per lane | - |
| D2 | 2026-11-03 | Engine is a standalone Python package (`looprun_engine`) the server imports | Game logic is testable on recorded tracks without Mongo, Redis or Flutter | plan section "Core rules" |
| D3 | 2026-11-03 | All work runs in the cloud workspace; the Mac mini is not used | User instruction, 2026-11-03 | user |
| D4 | 2026-11-03 | Flutter cannot be compiled in the cloud workspace (pub.dev, storage.googleapis.com and dl.google.com are blocked by the network allowlist). Mobile code is written here and compiled/analyzed/tested by GitHub Actions on GitHub's runners | Verified 2026-11-03: those hosts return 403 from the proxy; pypi, npm, conda-forge and GitHub raw are reachable | proxy status |
| D5 | 2026-11-03 | Docker daemon is not available in the cloud workspace; server tests use `fakeredis` and `mongomock-motor` locally, and CI runs against real Redis and MongoDB services | Verified: no docker.sock | - |
| D6 | 2026-11-03 | The session cannot create GitHub repos (API locked to configured repos). Work proceeds in a local git repo and is pushed once the user creates the empty repos | Verified: HTTP 403 on user/repos | gh api |
| D7 | 2026-11-03 | Contract change (additive): `Cell` and WebSocket `cell_changed` carry `lat` and `lng` of the cell centre. The mobile app drops the `h3_flutter` dependency | First CI run failed at `flutter pub get`: h3_flutter needs `js ^0.7.2` but flutter_secure_storage needs `js ^0.6.3`. Server already has the engine's cell_centre, so sending the centre is simpler and removes a risky dependency | CI log run 41691142803 |
| D8 | 2026-11-03 | The privacy copy is changed to match the app (location is also read once on request when centring the map or setting a home zone), not the app to match the copy | Verifier O1-C1 blocker 3; the behaviour is useful and low risk | docs/verification/O1-C1.md |
| D9 | 2026-11-11 | The monorepo is split. This repo (`looprun`) is the Flutter app, at the repo root (was `mobile/`, history kept via `git mv`). The backend (`engine/`, `server/`, `deploy/`, compose files, API contract) is in https://github.com/VivekMakwana24/looprun-backend with its history preserved by `git filter-repo`. The OpenAPI contract is owned by the backend repo; this repo keeps a snapshot at `docs/api/CONTRACT.openapi.yaml` | Separate CI, release and deploy cadence for app and backend | user request |

D2, D5 and D7 concern the backend; the backend repo carries its own excerpt of this log.
