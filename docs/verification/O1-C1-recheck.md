# Re-verification: O1 (DevOps) and C1 (Compliance)

Verifier: independent agent, 2026-11-04, repo state `7a24b07` on main (CI green). Read-only review: no code, workflow or other doc was edited; only this file is added.

## Verdict: REJECTED (narrowly). Two small blockers, otherwise most prior findings are properly fixed.

- B1 (DevOps): the production worker runs without celery beat, so the stuck-run sweeper never runs; adding `-B` alone will not work (read-only working directory).
- B2 (DevOps and Compliance): the release workflow does not pass `MAP_TILE_PROVIDER` or `PRIVACY_POLICY_URL`, so a release AAB shows the literal text `[MAP_TILE_PROVIDER]` and `[PRIVACY_POLICY_URL]` in the Play-required location disclosure.

With B1 and B2 fixed and the FIX items below applied, this is ACCEPT WITH FIXES. All the prior blockers (signing, dart-defines, location claim) are closed.

## What I ran

| Check | Result |
| --- | --- |
| `actionlint` 1.7.12 on all three workflows | 0 findings |
| `shellcheck -x -S style` on `deploy/*.sh`, `mobile/tool/*.sh` | Only SC2012 (info, `ls` in `check_manifest.sh:35`). Nothing else. |
| `docker compose config` dev file; prod file with a dummy env file | Both valid. Prod shows `LOOPRUN_DEV_AUTH: "0"` and only Caddy publishes ports. (No daemon here: nothing started, no image built.) |
| `make validate` | Passes and now loops over all five scripts. |
| `mobile/tool/patch_signing.sh` against a synthetic copy of the stock Flutter `build.gradle.kts`, run twice | Patches correctly, second run is a no-op, the `getByName("release")` line the workflow greps for is produced, no `getByName("debug")` left. Not run against a real Flutter-generated file or Gradle. |
| `pytest -m integration` | Cannot run here (`fakeredis` not installed, no Mongo/Redis). The test file and marker exist and the CI job exists; I did not see it run. |
| WebFetch of Play help pages 11926878 (target API) and 13327111 (account deletion) | See "Play requirements" below. |

Not run: Flutter/Gradle, any GitHub runner, `docker build`, ssh, mongodump/mongorestore, yamllint/caddy/hadolint (not installed).

## Status of the previous findings (O1-C1.md)

| # | Finding | Now |
| --- | --- | --- |
| 1 | Release signing never consumed | FIXED. `patch_signing.sh` plus step in `release-android.yml:62-72`, and a `jarsigner`/`keytool` check for "Android Debug" after the build (`:105-120`). Verified on a synthetic template only. |
| 2 | No dart-defines on release | PARTLY. `API_BASE_URL`, `GOOGLE_SERVER_CLIENT_ID`, `MAP_STYLE_URL` are required, https-checked, demo-server rejected. Two newer defines are missing: see B2. |
| 3 | "Location only during a run" contradicted by map and home-zone reads | FIXED by rewording. Policy, disclosure, listing, FGS declaration and tester guide now say the one-off map/home-zone read. Code matches: `getCurrentPosition` is called only from `map_screen.dart:31` (via `myPosition`) and `profile_repository.dart:99`; the position stream is only started for a run. |
| 4 | Deletion described as "unowned" | FIXED (policy, listing, in-app dialog all say handed to the strongest remaining player). Matches `processing.py` delete flow. |
| 5 | 90-day GPS retention not implemented | FIXED. 30 days, TTL index on `run_fixes.expire_at` (`resources.py:72`), accepted runs deleted at once; policy and Data safety say 30 days. Reports 180 days, TTL index (`resources.py:83`). |
| 6 | Crashlytics/Integrity described as collected | FIXED. Policy lists them as planned; Data safety rows removed; no `google-services.json` step. |
| 7 | Email described as stored | FIXED (policy: not stored). Matches `auth.py` (`google_sub`, `name`). See F5 for a knock-on problem. |
| 8 | Tile provider not disclosed | PARTLY. Policy, disclosure and Data safety now name a `[MAP_TILE_PROVIDER]` slot and flag the open decision. Still a placeholder and the production provider is not chosen. Release is blocked from the demo server. |
| 9 | FGS declaration claims a Stop action | FIXED, now true: `foreground_service.dart:25-26,108,122` set a Stop button. Not tried on a device; the doc says so. Preset wording now matches Google's three presets. |
| 10 | Reports / live not in app | Code now has both (`report_dialog.dart`, `live_service.dart`). Documents are now stale in the other direction: F1. |
| 11 | Disclosure doc differs from screen | FIXED for wording (strings are identical to `location-disclosure.md`). Remaining gaps: F3. |
| 12 | Deploy host key TOFU | FIXED. `LIGHTSAIL_HOST_KEY` mandatory (`deploy.yml:60`), written to known_hosts, ssh uses `StrictHostKeyChecking=yes -o BatchMode=yes` (`:76-78`). |
| 13 | JWT secret placeholder | FIXED. `setup-lightsail.sh:84-85` generates it (`openssl rand -hex 32`); prod compose requires it; server rejects secrets under 32 chars when dev auth is off (`config.py:28`). |
| 14 | CI claims real Mongo/Redis | FIXED structurally: separate `integration` job with service containers that fails if the tests were skipped. I could not see it run. |
| 15 | `make validate` | FIXED (loop). `prod-config` removed from `.PHONY`. CI now runs `docker compose config` on both files (`ci.yml` docker job). |
| 16 | Tester loop length, Android version | FIXED (600 m / about 1 km; Android 7+ matches minSdk 24). |
| 17 | Placeholder list | FIXED (README consolidated table). |
| 18-24 | Notes | Env var caveat resolved in RUNBOOK section 11. Item 21: still tag-pinned, see F7. Item 22: see F6. Items 23 and 24 re-checked against the server; still correct. |

Env vars: every `LOOPRUN_*` the compose files and `.env` template set matches an alias in `server/app/config.py` (`MONGO_URL`, `REDIS_URL`, `JWT_SECRET`, `GOOGLE_CLIENT_ID`, `DEV_AUTH`). No other `os.environ` reads in `server/app`.

## BLOCKERS

### B1. Worker has no beat; the sweeper never runs in production (and `-B` needs a writable schedule path)
- `docker-compose.prod.yml:32` and `docker-compose.yml:27`: `celery -A app.worker:celery_app worker --loglevel=info --concurrency=2`. `server/NOTES.md` (line 6) says the worker must be `... worker -B` (or a separate `beat`). `server/app/worker.py:42-44` only defines `beat_schedule`; nothing starts a scheduler. A repo grep finds no `-B`, `beat` or `schedule` in compose, RUNBOOK, Makefile or deploy scripts.
- Failure scenario: a worker is killed mid-task, or the broker message is lost, after a run was accepted. The run stays `processing` forever; the user's cells never update, the run keeps its raw GPS until the 30-day TTL backstop, and the app's upload queue polls it for ever. `/healthz` does not notice (NOTES says the sweeper is "not tied to /healthz"), and the deploy health check only calls the API.
- Not just a flag: `Dockerfile:23-24` makes `/app` root-owned and runs as uid 10001. Celery beat writes `celerybeat-schedule` into the current directory, so plain `-B` will fail to open its schedule file as that user and the embedded beat process dies while the worker keeps running (inferred from Celery's documented behaviour; I could not run it against the image here).
- Fix: in both compose files use `["celery","-A","app.worker:celery_app","worker","-B","-s","/tmp/celerybeat-schedule","--loglevel=info","--concurrency=2"]` (exactly one worker container may run `-B`), or add a separate `beat` service with the same `-s` path. Add a test or CI step that starts the image and checks the worker log for the beat start line, and add a `celery inspect ping` healthcheck for the worker (currently disabled at `docker-compose.prod.yml:34-35`) so a dead worker is visible in `docker compose ps`.

### B2. Release AAB ships placeholder text in the location disclosure
- `mobile/lib/core/config.dart:9-12` defaults `MAP_TILE_PROVIDER='[MAP_TILE_PROVIDER]'` and `PRIVACY_POLICY_URL='[PRIVACY_POLICY_URL]'`; `disclosure_screen.dart:29,55,84` render them. `release-android.yml:94-98` passes only the other three defines and the check step (`:30-52`) does not look at these two. `mobile/README.md:38-39` says "must be real in release", but nothing enforces it.
- Failure scenario: the workflow goes green, and the AAB's prominent disclosure reads "The map images are loaded from [MAP_TILE_PROVIDER]" and the Privacy Policy button shows "[PRIVACY_POLICY_URL]". That is a visible mismatch with the Play User Data policy (the disclosure must name use and sharing, and the policy link must work) and would be seen by testers and reviewers.
- Fix: add repository variables `MAP_TILE_PROVIDER` and `PRIVACY_POLICY_URL`; require both non-empty in the check step (reject values starting with `[`, require `https://` for the URL); pass them as `--dart-define`s; document them in RUNBOOK section 8. Optionally also fail if `DEV_AUTH` appears in the defines.

## FIX (should be done before the first Play submission)

### DevOps
- F6. `deploy/backup.sh`: the dump is written with the default umask and `/var/backups/looprun` is created 0755 (`setup-lightsail.sh:111`), so a full copy of all user data (Google IDs, names, home zones, held-run GPS) is world-readable on the host. Add `umask 077` and `chmod 700` on the directory. A failed dump also leaves `mongo-*.archive.gz.tmp`, which the `find ... -name 'mongo-*.archive.gz'` cleanup never matches (`:17-19`); add a trap or delete `*.tmp`. Also check the archive is non-empty before `mv`.
- F7. Supply chain and least privilege in `release-android.yml`: the signing secrets are set as job-level `env` (`:20-23`), so every third-party action in the job (`subosito/flutter-action`, `setup-java`) can read them. Move them to the two steps that need them. Add `environment: release` (with a branch restriction) so a modified workflow on a feature branch cannot dispatch and read the keystore secrets, and a `concurrency` group. Actions are pinned by tag (`@v4`, `@v2`), not SHA, and Flutter is `channel: stable` with no version; this also means the Play target API level (API 36 from 2026-08-31 per Google's page 11926878) depends on whatever stable Flutter ships that day. Pin the Flutter version and add a check that the AAB's `targetSdkVersion` is at least 36 (the stock template uses `flutter.targetSdkVersion`).
- F8. Server builds are not reproducible: the Dockerfile installs `./engine ./server` with unpinned dependency ranges and no lock file, and the host builds on every deploy. A bad upstream release can break a deploy mid-flight; there is no automatic rollback (RUNBOOK admits it). Consider a constraints file.
- F9. `setup-lightsail.sh` writes `LOOPRUN_DOMAIN=CHANGE_ME.example.com` and `LOOPRUN_GOOGLE_CLIENT_ID=CHANGE_ME...`; compose only requires them non-empty, so a forgotten edit starts Caddy trying to get a certificate for a fake name and sign-in silently fails. Add a placeholder check (`case ... *CHANGE_ME*) exit 1`) in the deploy step or a small `make prod-check`.
- F10. Still open from before and accepted as documented: Caddy waits for `api` started, not healthy (`docker-compose.prod.yml:77-78`); hard-coded `/opt/looprun/.env` (`:12`); no Mongo cache cap; backups local only; deploy gate depends on a CI run for the exact SHA, which expires with GitHub's run retention, so rolling back to a very old tag can be blocked.

### Compliance
- F1. Documents stale after mobile phase 2 (reporting and `/live` now exist in code):
  - `privacy-policy.md:32`: "the app does not offer reporting yet" is now false. The app sends a free-text reason (up to 500 characters, `report_dialog.dart:35`) plus the run or cell id to `POST /v1/reports`. State what is sent, that it can contain whatever the user types, retention 180 days, and add "free-text reports" to Data safety (Other user-generated content) and the policy's collection table.
  - `compliance/README.md:32-39` and `tester-guide.md:28` still say reporting and live updates are not in the build; the README is self-contradictory (a bullet says "Done in code, phase 2"). The listing does not advertise either, which is safe; update or remove when device-tested.
  - The policy does not mention the live socket: it carries the viewed bounding box (and the auth token in the first message). Add a line next to the bounding-box row.
- F2. On-device data is not described. The app keeps every finished run's raw GPS points in the local Drift database indefinitely: `discardRun` is the only per-run delete (`app_database.dart:122`) and uploaded runs are not removed; the data is wiped only on account deletion (`wipe`, `:160`), per account. Sign-out keeps it. `allowBackup="false"` is set, so it does not go to Google backup, which is good. The policy should say raw GPS of past runs stays on the phone until the account is deleted or the app is uninstalled, or the app should delete fixes after a successful upload. (Play's Data safety form covers data sent off the device, so the form is not affected.)
- F3. `location-disclosure.md` still carries "CHANGE" markers and says the mobile lane "must make" `mobile/lib/features/disclosure/disclosure_screen.dart` show the text. The strings are identical now, the path is wrong (`mobile/lib/ui/disclosure/disclosure_screen.dart`), and the doc line 35 promises a Privacy Policy link that "opens" the URL while the app only shows the URL in a selectable dialog (`disclosure_screen.dart:50-56`; no `url_launcher`). Update the doc to say so, or add `url_launcher`. A non-tappable policy link is weak against the Play requirement that the policy be reachable from the app.
- F4. Data safety and listing say account deletion "removes your runs and settings"; correct, but the form's own deletion rules (Play page 13327111) need a working **web** link where a user can request deletion without the app, naming the app or developer as on Google Play. `[ACCOUNT_DELETION_URL]` is still a placeholder; the policy only offers an email. Host the policy section and a request form/address, and enter it in the Data safety form.
- F5. The email deletion path cannot be carried out. `privacy-policy.md` ("Deleting your account") tells the user to write "from the address you use with Google and we will do it for you", but the server stores no email (`auth.py:115-129`: `google_sub`, `name`, no email). The operator cannot find the account from an email address. Either keep the email (and then change the policy, Data safety "Email address" to non-ephemeral, and retention) or provide a deletion path that identifies the account another way, for example a signed-in web deletion page or asking for the display name plus the date of the last run, or instruct users to use the in-app path or reinstall and sign in to delete.
- F11. The policy's "Server logs" gap: Caddy and uvicorn log client IP addresses, request paths and the bounding-box query string (the token is redacted, `Caddyfile` filter). The policy mentions only "may appear in server access logs". State the IP address, the retention of the logs (Docker's default `json-file` driver has no rotation limit set in compose), and set `logging: options: max-size/max-file` in prod compose.
- F12. FGS declaration: the notification Stop button exists in code but the verification notes say it is not device-tested; the declaration video shot list (step 5) offers either route, which is fine. Gate 1 must actually tap it before the video is recorded.
- F13. Items I checked against the server and found accurate: 30-day / 180-day TTLs, accepted-run GPS deleted at once, delete-account flow (cells reassigned, reports filed removed, reports about the user kept until expiry), home zones stored on the user document (up to five) and wiped with the account, owner name hidden at fewer than 3 users nearby (`privacy_min_users=3`), 30-minute delayed publishing, leaderboard lag, 14-day backups. The `listing.md` "Cells you own show your name" sentence now says "where enough runners are nearby", so finding 24 is closed.

## Play requirements checked

- Target API: Google's page 11926878 (fetched today) says new apps and updates must target API 36 from 2026-08-31 (extension to 2026-11-01). Today is after both dates, so the first upload must target 36. Not currently verified anywhere in CI (F7).
- Account deletion (page 13327111): needs an in-app path (present: Profile > Delete account) and a web link that works without the app, referencing the app or developer name; the Data safety deletion questions must be answered; retention for security or fraud reasons must be disclosed in the policy (the policy discloses the 30-day held-run retention and 14-day backups). The web link is the open item (F4).
- Prior verifier confirmations for closed testing (12 testers, 14 days), the location foreground-service declaration and the prominent-disclosure rules were not re-fetched; nothing in the code changed their applicability.
- Still unverified (correctly marked in the docs): Data safety form wording and the "service provider is not sharing" interpretation, ephemeral definition for email, IARC answers, Health apps declaration, listing limits.

## Suggested order

1. B1 and B2 (about an hour each, both small diffs).
2. F5 and F4 (deletion path), F1 and F2 (policy text), F6 (backup permissions).
3. F7 to F9, F3, F11, then the F10 items as time allows.

## Fixes applied (2026-11-04)

| Item | Change |
| --- | --- |
| B1 | Both compose files: worker runs `celery ... worker -B -s /tmp/celerybeat-schedule --loglevel=info --concurrency=2` (`/tmp` is world-writable in the image, so uid 10001 can write; a single worker container owns the beat). The disabled healthcheck is replaced by `celery -A app.worker:celery_app inspect ping -d celery@$HOSTNAME -t 5`. Checked locally with the real app against a local Redis: beat logged `beat: Starting...`, the schedule file was created under `/tmp`, and the ping returned `pong`. Not run inside the built image (no Docker daemon here). `server/NOTES.md`, `server/Dockerfile` comments and RUNBOOK section 4 updated. |
| B2 | `release-android.yml` reads `MAP_TILE_PROVIDER` and `PRIVACY_POLICY_URL` from repository variables, requires them non-empty, rejects values starting with `[` or containing `PLACEHOLDER` / `CHANGE_ME` (applies to all five variables), requires an `https://` policy URL, and passes both as `--dart-define`. The app does not use `ACCOUNT_DELETION_URL`, so it is not passed. RUNBOOK variable table updated. |
| F1, F2, F3 | Policy, Data safety (new optional "free-text reports" row), tester guide, compliance README and the disclosure doc now describe reports (free text up to 500 characters, 180 days), the `/live` connection (bounding box in the address, token in the first message), the Stop button, and raw GPS kept on the phone until account deletion or uninstall. Disclosure doc: CHANGE markers removed, correct path, and it states that the policy link is shown as selectable text and not opened. No code change, so the link is still not tappable (`url_launcher` is a recommended follow-up). |
| F4, F5 | The email deletion claim is removed: the server has no email, and acting on an emailed request would let anyone request deletion of another person's account, so an email path is not offered. Policy and listing now name in-app deletion as primary, reinstall-and-sign-in as the fallback, and a web page at `[ACCOUNT_DELETION_URL]` that verifies ownership by Google sign-in. **That page does not exist; it is an operator to-do** and the Data safety form should not be submitted until it does. |
| F6 | `deploy/backup.sh`: `umask 077`, `chmod 700` on the directory (also in `setup-lightsail.sh`), trap removes `*.tmp` on failure, empty dumps are rejected, stale `.tmp` files are swept with the old archives. Tested with a stub `docker` for failure, empty and success cases. |
| F7 (part) | Third-party actions pinned by commit SHA in all three workflows (tag in a comment; SHAs from `git ls-remote`, same major version as before): checkout v4.4.0, setup-java v4.9.1, upload-artifact v4.6.2, flutter-action v2.23.0, setup-python v5.6.0. Flutter pinned to 3.47.9 in `ci.yml` and the release workflow (CI now exercises the same version; if that version breaks the Flutter job, change both pins). Signing secrets moved from job `env` to the two steps that use them. Added a `concurrency` group. New step fails the release unless the merged release manifest has `targetSdkVersion >= 36`; Google's page (developer.android.com/google/play/requirements/target-sdk, fetched 2026-11-04) confirms API 36 for new apps and updates from 2026-08-31 (extension to 2026-11-01 has passed). That step has not run on a real runner and fails closed if the manifest path differs. |
| Not done | `environment: release` (needs the GitHub environment and branch rule created by the owner), F8, F9, F10, F11 (server log disclosure and log rotation), F12 (device test of the Stop button). |

Verification: actionlint 0 findings; shellcheck only the existing SC2012 info in `mobile/tool/check_manifest.sh`; `docker compose config` valid for both files (prod with a dummy env file, `$$HOSTNAME` renders correctly).
