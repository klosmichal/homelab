#!/usr/bin/env bash
# One-time root setup so scripts/backup.sh can run as the login user.
# Idempotent; re-run after every restic upgrade, because the copy below does not
# follow apt updates of /usr/bin/restic.
#
#   1. /usr/local/bin/restic-backup: a restic copy with cap_dac_read_search, so it
#      can read root-owned files and Docker volumes (but not write them).
#      Owned root:<user> 0750, so only that user can run it.
#   2. /var/log/homelab-backup.log, writable by the user
#   3. /etc/cron.d/homelab-backup: Sunday 03:00, as the user
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/setup-backup.sh"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
source "$ROOT_DIR/.env"
set +a

: "${RESTIC_BIN:=/usr/local/bin/restic-backup}"
: "${BACKUP_MOUNT_POINT:=/mnt/backup-usb}"
BACKUP_USER="$(id -nu "$PUID")"
CRON_FILE=/etc/cron.d/homelab-backup
LOG_FILE=/var/log/homelab-backup.log

if ! mountpoint -q "$BACKUP_MOUNT_POINT"; then
  echo "$BACKUP_MOUNT_POINT is not mounted — see docs/INSTALL.md §7b" >&2
  exit 1
fi
chown "$BACKUP_USER:$BACKUP_USER" "$BACKUP_MOUNT_POINT"

install -o root -g "$BACKUP_USER" -m 0750 "$(command -v restic)" "$RESTIC_BIN"
setcap cap_dac_read_search=+ep "$RESTIC_BIN"
echo "Installed $RESTIC_BIN ($("$RESTIC_BIN" version)): $(getcap "$RESTIC_BIN")"

touch "$LOG_FILE"
chown "$BACKUP_USER:$BACKUP_USER" "$LOG_FILE"

sed -e "s|@USER@|$BACKUP_USER|" -e "s|@ROOT_DIR@|$ROOT_DIR|" \
  "$ROOT_DIR/config/cron/homelab-backup" > "$CRON_FILE"
chmod 0644 "$CRON_FILE"
echo "Installed $CRON_FILE:"
grep -v '^#' "$CRON_FILE"
