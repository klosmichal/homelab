#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp --update=none "$ROOT_DIR/env/.env.example" "$ROOT_DIR/env/.env" 2>/dev/null || true
set -a
source "$ROOT_DIR/env/.env"
set +a

sudo mkdir -p \
  "$APPDATA_ROOT" \
  "$APPDATA_ROOT/adguardhome/conf" \
  "$APPDATA_ROOT/adguardhome/work" \
  "$APPDATA_ROOT/homeassistant/config" \
  "$APPDATA_ROOT/tailscale/state" \
  "$APPDATA_ROOT/samba" \
  "$MEDIA_ROOT/video" \
  "$MEDIA_ROOT/immich/library"

sudo chown -R "${PUID}:${PGID}" "$MEDIA_ROOT"

if [[ ! -f "$APPDATA_ROOT/adguardhome/conf/AdGuardHome.yaml" ]]; then
  sudo cp "$ROOT_DIR/config/adguardhome/AdGuardHome.yaml" "$APPDATA_ROOT/adguardhome/conf/AdGuardHome.yaml"
fi

if [[ ! -f "$APPDATA_ROOT/samba/smb.conf" ]]; then
  sudo cp "$ROOT_DIR/config/samba/smb.conf" "$APPDATA_ROOT/samba/smb.conf"
fi

echo "Folders are ready. Fill in passwords in env/.env and edit smb.conf if needed."
