#!/usr/bin/env bash
# First-boot setup for an Ubuntu (22.04/24.04) AWS Lightsail instance. Idempotent: safe to re-run.
#
#   sudo REPO_URL=https://github.com/<you>/looprun.git bash setup-lightsail.sh
#
# What it does: installs Docker (official apt repo), adds a 2 GB swap file, clones the repo to
# /opt/looprun, creates /opt/looprun/.env from a template (only if missing), installs a daily
# MongoDB backup cron job. It does NOT start the stack and does NOT touch the firewall.
set -euo pipefail

REPO_URL="${REPO_URL:-}"            # for a private repo use an SSH URL + deploy key, or https with a token
APP_DIR="${APP_DIR:-/opt/looprun}"
DEPLOY_USER="${DEPLOY_USER:-${SUDO_USER:-ubuntu}}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

log() { printf '\n==> %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

# ---- 1. Docker (official repository) ----
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log "Docker and compose plugin already installed"
else
  log "Installing Docker"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg git cron openssl
  install -m 0755 -d /etc/apt/keyrings
  if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
apt-get install -y git cron openssl >/dev/null
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  usermod -aG docker "$DEPLOY_USER"
fi

# ---- 2. Swap file (small instances run out of memory during image builds) ----
if swapon --show --noheadings | grep -q .; then
  log "Swap already active"
else
  log "Creating ${SWAP_SIZE_MB} MB swap file"
  if [ ! -f /swapfile ]; then
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB"
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---- 3. Repository checkout ----
if [ -d "$APP_DIR/.git" ]; then
  log "Repo already present at $APP_DIR"
else
  if [ -z "$REPO_URL" ]; then
    echo "REPO_URL is not set and $APP_DIR has no checkout. Re-run with REPO_URL=..." >&2
    exit 1
  fi
  log "Cloning $REPO_URL to $APP_DIR"
  mkdir -p "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
fi
chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$APP_DIR"
git config --global --add safe.directory "$APP_DIR" || true

# ---- 4. .env template (never overwritten) ----
ENV_FILE="$APP_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  log ".env already exists, leaving it alone"
else
  log "Creating $ENV_FILE template"
  MONGO_PW="$(openssl rand -hex 24)"
  JWT_SECRET="$(openssl rand -hex 32)"
  umask 077
  cat > "$ENV_FILE" <<ENVEOF
# Looprun production settings. Never commit this file. Keep it chmod 600.
# Every value marked CHANGE_ME must be set before the first deploy.

# Public hostname served by Caddy (DNS A record must point at this instance's static IP)
LOOPRUN_DOMAIN=CHANGE_ME.example.com

# MongoDB root password (generated for you; hex only so it is safe inside a connection URL)
MONGO_PASSWORD=${MONGO_PW}

# ---- App settings read by the server ----
LOOPRUN_GOOGLE_CLIENT_ID=CHANGE_ME.apps.googleusercontent.com
# Signs session tokens (generated for you; rotating it signs everyone out)
LOOPRUN_JWT_SECRET=${JWT_SECRET}
# Do NOT set LOOPRUN_DEV_AUTH in production.
ENVEOF
  umask 022
  chown "$DEPLOY_USER":"$DEPLOY_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

# ---- 5. Daily MongoDB backup (local disk only; offsite is future work) ----
if [ -f "$APP_DIR/deploy/backup.sh" ]; then
  chmod +x "$APP_DIR/deploy/backup.sh"
  mkdir -p /var/backups/looprun
  chmod 700 /var/backups/looprun
  cat > /etc/cron.d/looprun-backup <<CRONEOF
# Daily at 03:15 server time. Logs to /var/log/looprun-backup.log
15 3 * * * root APP_DIR=$APP_DIR $APP_DIR/deploy/backup.sh >> /var/log/looprun-backup.log 2>&1
CRONEOF
  chmod 644 /etc/cron.d/looprun-backup
fi

cat <<'DONE'

==============================================================
Setup finished. Remaining manual steps:

 1. Edit /opt/looprun/.env and replace every CHANGE_ME.
 2. Lightsail console > Networking: attach a STATIC IP, create the DNS A record,
    and in the instance firewall allow only TCP 22 (ideally restricted to your IP),
    TCP 80 and TCP 443. Do not open 27017 or 6379. (This script does not configure
    ufw so it cannot lock you out; Lightsail's own firewall is the control.)
 3. Add the GitHub Actions deploy public key to ~/.ssh/authorized_keys of the deploy user.
 4. First start:  cd /opt/looprun && docker compose -f docker-compose.prod.yml up -d --build
 5. Create an uptime monitor on https://YOUR_DOMAIN/healthz (see docs/RUNBOOK.md).
 6. Log out and back in so the docker group membership takes effect.
==============================================================
DONE
