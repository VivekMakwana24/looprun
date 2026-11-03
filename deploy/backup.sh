#!/usr/bin/env bash
# Dump MongoDB to a gzip archive on the local disk and delete archives older than KEEP_DAYS.
# Local only: if the instance dies the backups die with it. Offsite copy is future work (see RUNBOOK).
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/looprun}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/looprun}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/mongo-$STAMP.archive.gz"

mkdir -p "$BACKUP_DIR"
cd "$APP_DIR"
# The root password is already in the container's environment; expand it inside the container.
docker compose -f docker-compose.prod.yml exec -T mongo sh -c \
  'mongodump --quiet --uri="mongodb://looprun:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017/looprun?authSource=admin" --archive --gzip' \
  > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
find "$BACKUP_DIR" -name 'mongo-*.archive.gz' -mtime +"$KEEP_DAYS" -delete
echo "$(date -u +%FT%TZ) backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
