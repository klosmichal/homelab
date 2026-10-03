#!/usr/bin/env bash
# Weekly restic backup to the USB disk. Runs as the login user, not root:
# RESTIC_BIN is a restic copy carrying cap_dac_read_search (installed by
# scripts/setup-backup.sh), which lets it read root-owned files and Docker
# volumes without being able to write them.
#
# Three snapshots per run, one per tag, so each area restores on its own:
#   config — APPDATA_ROOT, this repo (incl. .env), compose-managed Docker volumes;
#            taken with the stack (except Tailscale) stopped so SQLite
#            databases are consistent
#   immich — photo library + a pg_dumpall of the Immich database
#   data   — USER_DATA_ROOT
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run as your login user, not root: bash scripts/backup.sh" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

: "${RESTIC_BIN:=/usr/local/bin/restic-backup}"
: "${BACKUP_MOUNT_POINT:=/mnt/backup-usb}"
VOLUMES=/var/lib/docker/volumes
PROJECT="${COMPOSE_PROJECT_NAME:-homelab}"
IMMICH_ROOT="$(dirname "$IMMICH_LIBRARY_ROOT")"
DUMP="$IMMICH_ROOT/db-dump/immich-postgres.sql"

restic() { "$RESTIC_BIN" "$@"; }
log() { printf '\n== %s  %s\n' "$(date '+%F %T')" "$*"; }

# --- Guards -----------------------------------------------------------------
if ! getcap "$RESTIC_BIN" 2>/dev/null | grep -q cap_dac_read_search; then
  echo "$RESTIC_BIN is missing or lacks cap_dac_read_search." >&2
  echo "Run: sudo bash scripts/setup-backup.sh (again after every restic upgrade)" >&2
  exit 1
fi
# The disk is mounted with nofail; without this check a missing disk would put
# the repository on the SSD.
if ! mountpoint -q "$BACKUP_MOUNT_POINT"; then
  echo "$BACKUP_MOUNT_POINT is not mounted. Plug in the backup disk and run: sudo mount -a" >&2
  exit 1
fi
if [[ ! -d "$(dirname "$DUMP")" ]]; then
  echo "$(dirname "$DUMP") is missing. Run: bash scripts/prepare-folders.sh" >&2
  exit 1
fi

if ! restic cat config >/dev/null 2>&1; then
  log "Initialising repository at $RESTIC_REPOSITORY"
  restic init
fi

# restic exits 3 when a snapshot was written but some files could not be read.
# Keep going so one bad file does not cost the other snapshots; fail at the end.
failed=0
snapshot() {
  local tag="$1"; shift
  log "Snapshot: $tag"
  local rc=0
  restic backup --tag "$tag" "$@" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "restic backup --tag $tag exited $rc" >&2
    failed=1
  fi
}

# --- Immich database dump (stack running) ------------------------------------
log "Dumping Immich database"
docker exec immich_postgres pg_dumpall --clean --if-exists --username="$IMMICH_DB_USER" > "$DUMP.tmp"
mv "$DUMP.tmp" "$DUMP"

# --- config (stack stopped) --------------------------------------------------
cd "$ROOT_DIR"
# Tailscale keeps running: its state is a small JSON file, and stopping it would
# cut off a `just backup` started remotely.
running=$(docker compose ps --services --status running | grep -vx tailscale || true)
restart_stack() {
  if [[ -n "$running" ]]; then
    log "Starting stack"
    # shellcheck disable=SC2086
    docker compose start $running
    running=""
  fi
}
trap restart_stack EXIT

log "Stopping stack"
# shellcheck disable=SC2086
[[ -n "$running" ]] && docker compose stop $running

snapshot config \
  --exclude "$APPDATA_ROOT/qbittorrent/config/Downloads" \
  --exclude "$APPDATA_ROOT/adguardhome/work/data/querylog.json*" \
  --exclude "$VOLUMES/${PROJECT}_jellyfin_config/_data/cache" \
  --exclude "$VOLUMES/${PROJECT}_jellyfin_config/_data/log" \
  --exclude "$VOLUMES/${PROJECT}_jellyfin_config/_data/data/transcodes" \
  --exclude "logs" \
  --exclude "*.log" \
  --exclude "*.log.[0-9]*" \
  "$APPDATA_ROOT" \
  "$ROOT_DIR" \
  "$VOLUMES/${PROJECT}_letsencrypt/_data" \
  "$VOLUMES/${PROJECT}_jellyfin_config/_data" \
  "$VOLUMES/${PROJECT}_portainer_data/_data" \
  "$VOLUMES/${PROJECT}_stirling_data/_data" \
  "$VOLUMES/${PROJECT}_filebrowser_data/_data" \
  "$VOLUMES/${PROJECT}_filebrowser_db/_data"

restart_stack

# .env is the only copy of the secrets; fail loudly if it did not make it in.
# (No grep -q: exiting early would SIGPIPE restic and trip pipefail.)
if ! restic ls latest --tag config "$ROOT_DIR" | grep -xF "$ROOT_DIR/.env" >/dev/null; then
  echo "$ROOT_DIR/.env is missing from the config snapshot" >&2
  failed=1
fi

# --- immich, data (live) -----------------------------------------------------
snapshot immich "$IMMICH_ROOT"
snapshot data "$USER_DATA_ROOT"

# --- Retention ---------------------------------------------------------------
log "Applying retention"
restic forget --group-by host,tags \
  --keep-weekly "$RESTIC_RETENTION_WEEKLY" \
  --keep-monthly "$RESTIC_RETENTION_MONTHLY" \
  --prune

log "Checking 5% of repository data"
restic check --read-data-subset=5% || failed=1

restic snapshots
exit $failed
