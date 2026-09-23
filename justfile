set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

# Copy the production example environment file
init-env:
  cp -n env.production.example .env

# Start all services, or a specific one: just up radarr
up *service:
  docker compose up -d {{service}}

# Stop all services, or a specific one: just stop radarr
stop *service:
  docker compose stop {{service}}

# Pull and recreate all services, or a specific one: just update radarr
update *service:
  docker compose pull {{service}}
  docker compose up -d {{service}}

# Show current container status
ps:
  docker compose ps --format "table {{{{.Name}}}}\t{{{{.Service}}}}\t{{{{.Status}}}}"

# Follow logs for all services, or a specific one: just logs radarr
logs *service:
  docker compose logs -f --tail=200 {{service}}

# Run the backup script
backup:
  bash ./scripts/backup.sh

# Run the smoke test script
check:
  bash ./scripts/healthcheck-smoke.sh

# Full post-restart verification: disks mounted, containers healthy, VPN up, routes answering
verify:
  bash ./scripts/verify.sh


# Show what differs between repo configs and the live runtime copies
diff-config:
  bash ./scripts/config-sync.sh diff

# Copy runtime configs back into the repo (reverse of sync-config)
pull-config:
  bash ./scripts/config-sync.sh pull

# Copy all configs from repo to runtime locations and restart affected containers
sync-config:
  #!/usr/bin/env bash
  set -uo pipefail
  bash ./scripts/config-sync.sh push
  rc=$?
  if [ $rc -eq 2 ]; then echo "Containers not restarted."; exit 0; fi
  [ $rc -eq 0 ] || exit $rc
  docker compose restart adguardhome samba qbittorrent homepage gluetun recyclarr homeassistant
