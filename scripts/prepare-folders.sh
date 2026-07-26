#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp --update=none "$ROOT_DIR/env.production.example" "$ROOT_DIR/.env" 2>/dev/null || true
set -a
source "$ROOT_DIR/.env"
set +a

# App data directories
sudo mkdir -p \
  "$APPDATA_ROOT" \
  "$APPDATA_ROOT/adguardhome/conf" \
  "$APPDATA_ROOT/adguardhome/work" \
  "$APPDATA_ROOT/homeassistant/config" \
  "$APPDATA_ROOT/tailscale/state" \
  "$APPDATA_ROOT/samba" \
  "$APPDATA_ROOT/gluetun" \
  "$APPDATA_ROOT/qbittorrent/config/qBittorrent" \
  "$APPDATA_ROOT/prowlarr/config" \
  "$APPDATA_ROOT/radarr/config" \
  "$APPDATA_ROOT/sonarr/config" \
  "$APPDATA_ROOT/bazarr/config" \
  "$APPDATA_ROOT/seerr/config"

sudo chown -R 1000:1000 "$APPDATA_ROOT/seerr"

# Media directories (MEDIA_ROOT lives on external HDD)
sudo mkdir -p \
  "$MEDIA_ROOT/video/movies" \
  "$MEDIA_ROOT/video/shows" \
  "$MEDIA_ROOT/downloads/complete" \
  "$MEDIA_ROOT/downloads/incomplete"

sudo chown -R "${PUID}:${PGID}" "$MEDIA_ROOT"

# Immich library stays on the SSD (IMMICH_LIBRARY_ROOT), separate from MEDIA_ROOT
sudo mkdir -p "$IMMICH_LIBRARY_ROOT"
sudo chown -R "${PUID}:${PGID}" "$IMMICH_LIBRARY_ROOT"

# Config files — copy only on first run; use just sync-config to re-apply
if [[ ! -f "$APPDATA_ROOT/adguardhome/conf/AdGuardHome.yaml" ]]; then
  sudo cp "$ROOT_DIR/config/adguardhome/AdGuardHome.yaml" "$APPDATA_ROOT/adguardhome/conf/AdGuardHome.yaml"
fi

if [[ ! -f "$APPDATA_ROOT/samba/smb.conf" ]]; then
  sudo cp "$ROOT_DIR/config/samba/smb.conf" "$APPDATA_ROOT/samba/smb.conf"
fi

if [[ ! -f "$APPDATA_ROOT/qbittorrent/config/qBittorrent/qBittorrent.conf" ]]; then
  sudo cp "$ROOT_DIR/config/qbittorrent/qBittorrent.conf" "$APPDATA_ROOT/qbittorrent/config/qBittorrent/qBittorrent.conf"
  sudo chown "${PUID}:${PGID}" "$APPDATA_ROOT/qbittorrent/config/qBittorrent/qBittorrent.conf"
fi

# Traefik basic auth — protects all *_HOST routes via the traefik-auth middleware
TRAEFIK_USERS_FILE="$ROOT_DIR/config/traefik/traefik-users"
if [[ ! -f "$TRAEFIK_USERS_FILE" ]]; then
  echo ""
  echo "Traefik basic auth (secures all services behind *.michalklos.com):"
  read -rp "  Username [admin]: " TRAEFIK_USER
  TRAEFIK_USER="${TRAEFIK_USER:-admin}"
  read -rsp "  Password: " TRAEFIK_PASS
  echo
  if command -v htpasswd &>/dev/null; then
    htpasswd -Bnb "$TRAEFIK_USER" "$TRAEFIK_PASS" > "$TRAEFIK_USERS_FILE"
  else
    docker run --rm httpd:2 htpasswd -Bnb "$TRAEFIK_USER" "$TRAEFIK_PASS" > "$TRAEFIK_USERS_FILE"
  fi
  echo "  Written to config/traefik/traefik-users"
fi

echo "Folders are ready. Fill in passwords in .env and edit smb.conf if needed."
