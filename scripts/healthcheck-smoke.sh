#!/usr/bin/env bash
set -euo pipefail

for c in \
  traefik adguardhome tailscale \
  homepage dozzle \
  jellyfin homeassistant \
  filebrowser samba \
  immich_server immich_machine_learning immich_redis immich_postgres \
  portainer stirling_pdf \
  gluetun qbittorrent \
  prowlarr radarr sonarr bazarr seerr; do
  docker ps --format '{{.Names}}' | grep -q "^${c}$" && echo "OK: $c" || echo "MISSING: $c"
done
