#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

STAMP=$(date +%F-%H%M%S)
TMP_DIR="/tmp/homelab-backup-$STAMP"
mkdir -p "$TMP_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

docker exec immich_postgres pg_dump -U "$IMMICH_DB_USER" "$IMMICH_DB_NAME" > "$TMP_DIR/immich-postgres.sql"

restic init 2>/dev/null || true
restic backup \
  "$BACKUP_SOURCE_1" \
  "$BACKUP_SOURCE_2" \
  "$TMP_DIR/immich-postgres.sql"

restic forget --keep-weekly "$RESTIC_RETENTION_WEEKLY" --keep-monthly "$RESTIC_RETENTION_MONTHLY" --prune
restic snapshots
