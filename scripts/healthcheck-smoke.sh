#!/usr/bin/env bash
set -euo pipefail

for c in traefik homarr jellyfin vaultwarden immich_server uptime_kuma stirling_pdf portainer dozzle; do
  docker ps --format '{{.Names}}' | grep -q "^${c}$" && echo "OK: $c" || echo "MISSING: $c"
done
