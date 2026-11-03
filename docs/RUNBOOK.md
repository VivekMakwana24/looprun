# Looprun runbook

Single Lightsail host, Docker Compose, Caddy for HTTPS. Everything below assumes the repo is checked out at `/opt/looprun` and settings live in `/opt/looprun/.env` (gitignored, chmod 600).

Status of this document: written without access to a running host or Docker daemon. Nothing here has been executed yet; treat the first deploy as the test and fix this file with what you learn.

## 1. First-time host setup

1. Create an Ubuntu 22.04/24.04 Lightsail instance (2 GB RAM or more recommended; the swap file helps image builds on smaller ones).
2. Lightsail console: attach a **static IP**, point a DNS A record (for example `api.example.com`) at it.
3. Lightsail firewall: allow TCP 22 (restrict to your IP if you can), 80, 443. Do not open 27017 or 6379.
4. SSH in and run:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/<you>/looprun/main/deploy/setup-lightsail.sh -o setup.sh   # or scp it
   sudo REPO_URL=https://github.com/<you>/looprun.git bash setup.sh
   ```
   For a private repo, create a read-only deploy key on the host (`ssh-keygen -t ed25519`), add the public half under the repo's Settings > Deploy keys, and use the `git@github.com:<you>/looprun.git` URL.
5. Edit `/opt/looprun/.env` (replace every `CHANGE_ME`).
6. Add the GitHub Actions deploy key (section 8) to `~/.ssh/authorized_keys` of the deploy user.
7. First start: `cd /opt/looprun && docker compose -f docker-compose.prod.yml up -d --build`.

The script is idempotent; re-running it never overwrites `.env`.

## 2. Deploy

Deploys are done by `.github/workflows/deploy.yml`, on a `v*` tag or by hand (Actions > Deploy > Run workflow, choose the ref).

```bash
git checkout main && git pull
git tag v0.1.0 && git push origin v0.1.0
```

The workflow first runs a gate that **refuses to deploy** unless (a) the commit is contained in `origin/main` and (b) `gh run list --workflow ci.yml --commit <sha> --status success` finds a green CI run. If you tag the instant you push, CI may still be running and the gate fails; wait for green and re-run the workflow.

Then it SSHes to the host, runs `git fetch --tags`, `git checkout --detach <sha>` (deploys the exact reviewed commit rather than whatever `git pull` would fetch), and `docker compose -f docker-compose.prod.yml up -d --build --remove-orphans`. Finally it curls `LOOPRUN_HEALTH_URL` with retries and fails the job if unhealthy.

Manual deploy on the host (same thing):
```bash
cd /opt/looprun && git fetch --tags origin && git checkout --detach <sha-or-tag>
docker compose -f docker-compose.prod.yml up -d --build
```

## 3. Rollback

Redeploy an earlier known-good tag or commit. It is on main and had green CI, so the gate lets it through.

- GitHub: Actions > Deploy > Run workflow, select the old tag from the ref dropdown.
- Or on the host: `git checkout --detach v0.0.9 && docker compose -f docker-compose.prod.yml up -d --build`.

Database changes are not rolled back by this. If a release changed data shape, restore from a backup (section 5) after stopping the stack. Prefer additive-only data changes so rollback stays safe.

## 4. Logs, status, restart

```bash
cd /opt/looprun
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f --tail=200 api
docker compose -f docker-compose.prod.yml logs -f --tail=200 worker
docker compose -f docker-compose.prod.yml logs --tail=100 caddy      # certificate problems show here
docker compose -f docker-compose.prod.yml restart api worker
docker compose -f docker-compose.prod.yml down                       # stop all (volumes are kept)
```

Containers use `restart: unless-stopped`, so they come back after a reboot as long as the Docker service is enabled (the setup script does that).

## 5. Backups

`deploy/backup.sh` runs `mongodump --archive --gzip` inside the mongo container and writes `/var/backups/looprun/mongo-<UTC timestamp>.archive.gz`, deleting archives older than 14 days (`KEEP_DAYS`). The setup script installs it as `/etc/cron.d/looprun-backup` (daily 03:15 server time, log in `/var/log/looprun-backup.log`).

Run one now: `sudo /opt/looprun/deploy/backup.sh`

Restore (destructive for the named database):
```bash
cd /opt/looprun
docker compose -f docker-compose.prod.yml exec -T mongo sh -c \
  'mongorestore --uri="mongodb://looprun:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017/?authSource=admin" --archive --gzip --drop' \
  < /var/backups/looprun/mongo-XXXX.archive.gz
```

**Limitation:** these backups sit on the same disk as the database. If the instance is lost, so are they. Future work: offsite copy (for example `aws s3 cp` to a private S3 bucket, or Lightsail automatic snapshots, which are a cheap stopgap). Redis holds queue state only and is not backed up. Test a restore on a scratch instance before you rely on this.

## 6. Rotating secrets

| Secret | Where | How to rotate |
| --- | --- | --- |
| `LOOPRUN_JWT_SECRET` | `/opt/looprun/.env` | Edit, then `docker compose -f docker-compose.prod.yml up -d` (recreates api/worker). All users are signed out and sign in again. |
| `MONGO_PASSWORD` | `/opt/looprun/.env` | The password is only applied when the data volume is first created. Change it in Mongo first: `docker compose -f docker-compose.prod.yml exec mongo mongosh -u looprun -p --authenticationDatabase admin` then `db.getSiblingDB('admin').changeUserPassword('looprun','<new hex>')`; then edit `.env` and `up -d`. |
| `LOOPRUN_GOOGLE_CLIENT_ID` | `.env` and the app | Only changes if you create a new OAuth client; the app build must match. |
| `LIGHTSAIL_SSH_KEY` | GitHub secret | Generate a new key pair, append the new public key to the host's `authorized_keys`, update the secret, run a deploy, then delete the old public key line. |
| Android keystore | GitHub secrets | See section 9. The upload key can be reset via Play Console support if lost (Play App Signing); keep an offline copy anyway. |

If a secret leaked: rotate it, then check `docker compose ... logs` and Caddy logs for misuse.

## 7. Uptime check (free)

The API exposes `GET /healthz`. Use a free external monitor so you hear about outages from a service outside the host:

- UptimeRobot (free plan: HTTPS monitor, 5-minute interval, email alerts) or Better Stack / Freshping equivalents. Plan limits change; check the current free tier.
- Create an HTTPS monitor for `https://<LOOPRUN_DOMAIN>/healthz`, expect HTTP 200, alert to your email or phone.
- Optional second check on the TLS certificate expiry (Caddy renews automatically; this catches a failed renewal).
- Use the same URL for the GitHub secret `LOOPRUN_HEALTH_URL`.

## 8. GitHub Actions secrets

Settings > Secrets and variables > Actions. The deploy job uses the `production` environment (Settings > Environments); you can add required reviewers there for a manual approval step.

| Secret | Used by | Value |
| --- | --- | --- |
| `LIGHTSAIL_HOST` | deploy | Static IP or hostname of the instance |
| `LIGHTSAIL_USER` | deploy | SSH user (for example `ubuntu`); must be in the `docker` group |
| `LIGHTSAIL_SSH_KEY` | deploy | Private key (full PEM/OpenSSH text) of a key dedicated to deploys. Create with `ssh-keygen -t ed25519 -f looprun_deploy -C github-deploy -N ""`, put `looprun_deploy.pub` on the host, paste `looprun_deploy` into the secret, delete the local copy. |
| `LIGHTSAIL_HOST_KEY` | deploy (optional but recommended) | Host public key line without the hostname, for example `ssh-ed25519 AAAA...`. Get it with `ssh-keyscan -t ed25519 <host>` from a network you trust. If unset, the workflow trusts the key on first contact and prints a warning. |
| `LOOPRUN_HEALTH_URL` | deploy | `https://<domain>/healthz` |
| `ANDROID_KEYSTORE_B64` | release-android | Base64 of the upload keystore (section 9) |
| `ANDROID_KEYSTORE_PASSWORD` | release-android | Keystore password |
| `ANDROID_KEY_PASSWORD` | release-android | Key password |
| `ANDROID_KEY_ALIAS` | release-android | Key alias (for example `upload`) |
| `GOOGLE_SERVICES_JSON_B64` | release-android (optional) | Base64 of Firebase `google-services.json`, needed for Crashlytics. Not a high-grade secret but keep it out of the repo. |

`GITHUB_TOKEN` is provided automatically; the deploy gate uses it with `actions: read`.

## 9. Android release signing

The release workflow `.github/workflows/release-android.yml` (manual trigger) builds a **signed AAB** and uploads it as the workflow artifact `looprun-release-aab`. It does not publish to Google Play; download it and upload it in the Play Console.

Create the upload keystore on your own machine (once). Never commit it:
```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks > upload-keystore.b64      # macOS: base64 -i upload-keystore.jks -o upload-keystore.b64
```
Paste the contents of `upload-keystore.b64` into secret `ANDROID_KEYSTORE_B64`, and set the passwords and alias secrets. Store the `.jks` file and passwords in a password manager plus one offline backup, then delete `upload-keystore.b64`. Enrol in **Play App Signing** when creating the app in Play Console: Google holds the real app-signing key and your keystore is only the upload key, which Google can reset if you lose it.

How the workflow signs: it writes `mobile/android/app/upload-keystore.jks` and `mobile/android/key.properties` (`storePassword`, `keyPassword`, `keyAlias`, `storeFile`) on the runner only. **Dependency on the mobile lane:** `mobile/tool/bootstrap.sh` (or the Gradle file it produces) must make `android/app/build.gradle(.kts)` read `key.properties` and use it for the `release` signing config. If that is missing, the build will be signed with the debug key, which Play rejects. Verify once by running the workflow and checking the AAB with `keytool -printcert -jarfile app-release.aab`.

Other release steps: bump `version:` in `mobile/pubspec.yaml` (build number must increase on every upload), run the workflow, upload the AAB to the closed test track (see `docs/compliance/closed-test-checklist.md`).

## 10. CI overview

`.github/workflows/ci.yml` runs on every push and PR: Python (ruff, pytest for engine and server against real Redis and MongoDB services), Flutter (bootstrap, analyze, test, debug APK uploaded as `looprun-debug-apk`), Docker (image build only, nothing is pushed). Local equivalents: `make lint`, `make test`, `make build`.

## 11. Known gaps

- Server environment variable names in `.env` and compose (`LOOPRUN_MONGO_URL`, `LOOPRUN_REDIS_URL`, `LOOPRUN_GOOGLE_CLIENT_ID`, `LOOPRUN_JWT_SECRET`) are assumptions until reconciled with `server/app`.
- Backups are local only.
- Single host, single instance: a deploy causes a short outage while containers are recreated.
- Nothing here has been executed against a real Docker daemon or GitHub runner by the author.
