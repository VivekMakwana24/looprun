# Decisions log

| # | Date | Decision | Why | Source |
| --- | --- | --- | --- | --- |
| D1 | 2026-11-03 | Monorepo `looprun` with `engine/`, `server/`, `mobile/`, `docs/` | One place for contract, CI and board; folders are owned per lane | - |
| D2 | 2026-11-03 | Engine is a standalone Python package (`looprun_engine`) the server imports | Game logic is testable on recorded tracks without Mongo, Redis or Flutter | plan section "Core rules" |
| D3 | 2026-11-03 | All work runs in the cloud workspace; the Mac mini is not used | User instruction, 2026-11-03 | user |
| D4 | 2026-11-03 | Flutter cannot be compiled in the cloud workspace (pub.dev, storage.googleapis.com and dl.google.com are blocked by the network allowlist). Mobile code is written here and compiled/analyzed/tested by GitHub Actions on GitHub's runners | Verified 2026-11-03: those hosts return 403 from the proxy; pypi, npm, conda-forge and GitHub raw are reachable | proxy status |
| D5 | 2026-11-03 | Docker daemon is not available in the cloud workspace; server tests use `fakeredis` and `mongomock-motor` locally, and CI runs against real Redis and MongoDB services | Verified: no docker.sock | - |
| D6 | 2026-11-03 | The session cannot create GitHub repos (API locked to configured repos). Work proceeds in a local git repo and is pushed once the user creates the empty repos | Verified: HTTP 403 on user/repos | gh api |
