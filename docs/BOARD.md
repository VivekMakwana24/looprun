# Board (updated by the project manager)

Status values: todo, building, verifying, accepted, blocked

| ID | Module | Lane | Status | Acceptance criteria |
| --- | --- | --- | --- | --- |
| E1 | Engine: clean fixes, loops, cells, flags | Engine | building | docs/ENGINE_SPEC.md behaviour 1-7; all fixtures pass; `pytest engine` green |
| E2 | Engine: ownership, decay, freeze, simulation, replay tool | Engine | building | docs/ENGINE_SPEC.md behaviour 8; simulate.py shows steady beats one fast run |
| S1 | Server: config, auth (Google + dev), Mongo/Redis wiring, health | Server | building | `pytest server` green; /v1/auth/google dev flow works |
| S2 | Server: POST/GET runs, queue, worker using engine | Server | building | idempotent upload; status moves processing to accepted/pending_review; cells written |
| S3 | Server: cells, leaderboard, home zones, freeze, delete, reports, WebSocket | Server | building | matches docs/CONTRACT.openapi.yaml; privacy rules in docs plan "Privacy defaults" |
| M1 | Mobile: project, recorder service, Drift buffer, upload queue | Mobile | building | `flutter analyze` and `flutter test` green in CI (cannot compile in cloud) |
| M2 | Mobile: sign-in, disclosure, map, run, result, settings screens | Mobile | building | screens per plan "Mobile app"; widget tests |
| O1 | DevOps: Dockerfiles, compose, CI workflows, deploy workflow | DevOps | building | workflows lint clean; compose file valid; deploy workflow documented |
| C1 | Compliance: privacy policy, data safety answers, in-app disclosure text, listing copy, tester guide | Store | building | text complete, matches real behaviour |
| L1 | Letter assistant | Letter | todo | starts after repo exists |

Verification: every module is checked by a separate verifier agent before it moves to accepted.
