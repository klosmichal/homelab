#!/usr/bin/env bash
cat <<'TXT'
Restore quick notes
===================
Every backup run writes three snapshots, one per tag:
  config — /srv/homelab, this repo (incl. .env), Docker volumes
           (letsencrypt, jellyfin_config, portainer_data, stirling_data, filebrowser_*)
  immich — /srv/data/immich: photo library + db-dump/immich-postgres.sql
  data   — /mnt/data

Restoring writes root-owned files, so it uses the stock restic under sudo; the
capability copy (restic-backup) can only read. Load the repo location and
password first:
  set -a; source .env; set +a
  just snapshots config          # pick a snapshot ID, or use "latest"

Roll back one service (example: radarr):
  just stop radarr
  sudo -E restic restore latest --tag config --target / --include /srv/homelab/radarr
  just up radarr
For a service on a Docker volume, include its volume instead, e.g.
  --include /var/lib/docker/volumes/homelab_jellyfin_config

Look before restoring:
  restic-backup ls latest --tag config /srv/homelab/radarr
  restic-backup restore latest --tag config --target /tmp/restore-test --include <path>

Recover .env alone:
  RESTIC_REPOSITORY=/mnt/backup-usb/restic restic dump latest --tag config /home/mklos/homelab/.env > .env

Full rebuild:
  1. Install the OS, run scripts/install-host.sh, mount the backup disk (INSTALL.md §7b).
  2. Restore .env as above (asks for the restic password), then the repo:
     sudo -E restic restore latest --tag config --target / --include /home/mklos/homelab
  3. sudo -E restic restore latest --tag config --target /
     sudo -E restic restore latest --tag immich --target /
     sudo -E restic restore latest --tag data   --target /
  4. just up, then load the Immich database into a fresh immich_postgres following
     https://immich.app/docs/administration/backup-and-restore (dump file:
     /srv/data/immich/db-dump/immich-postgres.sql, made with pg_dumpall --clean).
TXT
