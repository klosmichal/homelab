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
  docker compose ps

# Follow logs for all services, or a specific one: just logs radarr
logs *service:
  docker compose logs -f --tail=200 {{service}}

# Run the backup script
backup:
  bash ./scripts/backup.sh

# Run the smoke test script
check:
  bash ./scripts/healthcheck-smoke.sh

# --- Temporary surprise-app at wwa.michalklos.com (remove after use) ---

# Clone (or update) the app source onto the host
wwa-clone:
  git clone https://github.com/klosmichal/surprise-app.git ${APPDATA_ROOT:-/srv/homelab}/wwa/app \
    || git -C ${APPDATA_ROOT:-/srv/homelab}/wwa/app pull

# Build the image and start the temporary wwa stack
wwa-up:
  docker compose -f docker-compose.wwa.yml up -d --build

# Follow logs for the wwa stack
wwa-logs:
  docker compose -f docker-compose.wwa.yml logs -f --tail=200

# Tear down the wwa stack (leaves the cloned source on disk)
wwa-down:
  docker compose -f docker-compose.wwa.yml down

# Full cleanup: stop, remove the built image + data volume, and delete the clone
wwa-purge:
  docker compose -f docker-compose.wwa.yml down --rmi local -v
  rm -rf ${APPDATA_ROOT:-/srv/homelab}/wwa

# Copy runtime configs back into the repo (reverse of sync-config)
pull-config:
  cp ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf/AdGuardHome.yaml config/adguardhome/AdGuardHome.yaml
  cp ${APPDATA_ROOT:-/srv/homelab}/samba/smb.conf config/samba/smb.conf
  cp ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent/qBittorrent.conf config/qbittorrent/qBittorrent.conf
  cp ${APPDATA_ROOT:-/srv/homelab}/gluetun/auth/config.toml config/gluetun/auth/config.toml

# Copy all configs from repo to runtime locations and restart affected containers
sync-config:
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/samba
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/homepage/config
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/gluetun/auth
  cp config/adguardhome/AdGuardHome.yaml ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf/AdGuardHome.yaml
  cp config/samba/smb.conf ${APPDATA_ROOT:-/srv/homelab}/samba/smb.conf
  cp config/qbittorrent/qBittorrent.conf ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent/qBittorrent.conf
  cp config/homepage/* ${APPDATA_ROOT:-/srv/homelab}/homepage/config/
  cp config/gluetun/auth/config.toml ${APPDATA_ROOT:-/srv/homelab}/gluetun/auth/config.toml
  docker compose restart adguardhome samba qbittorrent homepage gluetun
