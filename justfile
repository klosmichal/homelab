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

# Copy runtime configs back into the repo (reverse of sync-config)
pull-config:
  cp ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf/AdGuardHome.yaml config/adguardhome/AdGuardHome.yaml
  cp ${APPDATA_ROOT:-/srv/homelab}/samba/smb.conf config/samba/smb.conf
  cp ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent/qBittorrent.conf config/qbittorrent/qBittorrent.conf

# Copy all configs from repo to runtime locations and restart affected containers
sync-config:
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/samba
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent
  mkdir -p ${APPDATA_ROOT:-/srv/homelab}/homepage/config
  cp config/adguardhome/AdGuardHome.yaml ${APPDATA_ROOT:-/srv/homelab}/adguardhome/conf/AdGuardHome.yaml
  cp config/samba/smb.conf ${APPDATA_ROOT:-/srv/homelab}/samba/smb.conf
  cp config/qbittorrent/qBittorrent.conf ${APPDATA_ROOT:-/srv/homelab}/qbittorrent/config/qBittorrent/qBittorrent.conf
  cp config/homepage/* ${APPDATA_ROOT:-/srv/homelab}/homepage/config/
  docker compose restart adguardhome samba qbittorrent homepage
