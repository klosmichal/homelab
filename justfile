set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

# Copy the production example environment file
init-env:
  cp -n env/env.production.example env/.env

# Start the core stack only
up:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Stop the stack
stop:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml down

# Pull updated images and recreate containers
update:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml pull
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Show current container status
ps:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml ps

# Follow logs for all services
logs:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml logs -f --tail=200

# Run the backup script
backup:
  bash ./scripts/backup.sh

# Run the smoke test script
check:
  bash ./scripts/healthcheck-smoke.sh

# Copy all configs from repo to runtime locations and restart affected containers
sync-config:
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/samba
  cp config/adguardhome/AdGuardHome.yaml ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf/AdGuardHome.yaml
  cp config/samba/smb.conf ${APPDATA_ROOT:-/srv/homelab}/samba/smb.conf
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml restart adguardhome samba
