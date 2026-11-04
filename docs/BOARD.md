# Board (updated by the project manager)

Status values: todo, building, verifying, accepted, blocked

| ID | Module | Lane | Status | Acceptance criteria |
| --- | --- | --- | --- | --- |
| E1 | Engine: clean fixes, loops, cells, flags | Engine | accepted (verifier: accept with fixes; see docs/verification/E1-E2.md) | docs/ENGINE_SPEC.md behaviour 1-7; all fixtures pass; `pytest engine` green |
| E2 | Engine: ownership, decay, freeze, simulation, replay tool | Engine | accepted (verifier: accept with fixes; see docs/verification/E1-E2.md) | docs/ENGINE_SPEC.md behaviour 8; simulate.py shows steady beats one fast run |
| S1 | Server: config, auth (Google + dev), Mongo/Redis wiring, health | Server | accepted with fixes (second-pass verifier, docs/verification/S-recheck.md; fix wave 2 running) | `pytest server` green; /v1/auth/google dev flow works |
| S2 | Server: POST/GET runs, queue, worker using engine | Server | accepted with fixes (second-pass verifier, docs/verification/S-recheck.md; fix wave 2 running) | idempotent upload; status moves processing to accepted/pending_review; cells written |
| S3 | Server: cells, leaderboard, home zones, freeze, delete, reports, WebSocket | Server | accepted with fixes (second-pass verifier, docs/verification/S-recheck.md; fix wave 2 running) | matches docs/CONTRACT.openapi.yaml; privacy rules in docs plan "Privacy defaults" |
| M1 | Mobile: project, recorder service, Drift buffer, upload queue | Mobile | building | `flutter analyze` and `flutter test` green in CI (cannot compile in cloud) |
| M2 | Mobile: sign-in, disclosure, map, run, result, settings screens | Mobile | building | screens per plan "Mobile app"; widget tests |
| O1 | DevOps: Dockerfiles, compose, CI workflows, deploy workflow | DevOps | verifying (fixes applied; re-verify after mobile lands) | workflows lint clean; compose file valid; deploy workflow documented |
| C1 | Compliance: privacy policy, data safety answers, in-app disclosure text, listing copy, tester guide | Store | verifying (fixes applied; re-verify after mobile lands) | text complete, matches real behaviour |
| SF1 (done in fix wave 1) | Server fix: when a freeze starts, rebase user's cell_power to faded(now) with updated_at=now-grace; skip apply_claim when credit is 0; enforce max_freeze_days; validate Config | Server | todo | tests for each; from engine verifier findings 1,2,7 |
| L1 | Letter assistant | Letter | todo | starts after repo exists |

Verification: every module is checked by a separate verifier agent before it moves to accepted.
