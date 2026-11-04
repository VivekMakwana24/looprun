#!/usr/bin/env bash
# Dump MongoDB to a gzip archive on the local disk and delete archives older than KEEP_DAYS.
# Local only: if the instance dies the backups die with it. Offsite copy is future work (see RUNBOOK).
set -euo pipefail
umask 077   # backups hold all user data (Google ids, names, home zones, held-run GPS): owner-only

APP_DIR="${APP_DIR:-/opt/looprun}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/looprun}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/mongo-$STAMP.archive.gz"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
# Remove the partial file if anything below fails (mongodump error, empty output, full disk).
trap 'rm -f "$OUT.tmp"' EXIT
cd "$APP_DIR"
# The root password is already in the container's environment; expand it inside the container.
docker compose -f docker-compose.prod.yml exec -T mongo sh -c \
  'mongodump --quiet --uri="mongodb://looprun:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017/looprun?authSource=admin" --archive --gzip' \
  > "$OUT.tmp"
if [ ! -s "$OUT.tmp" ]; then
  echo "backup failed: mongodump produced an empty archive" >&2
  exit 1
fi
mv "$OUT.tmp" "$OUT"
# Also sweep stale partial files left by a killed run (a trap cannot run on SIGKILL).
find "$BACKUP_DIR" \( -name 'mongo-*.archive.gz' -o -name 'mongo-*.archive.gz.tmp' \) -mtime +"$KEEP_DAYS" -delete
echo "$(date -u +%FT%TZ) backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
