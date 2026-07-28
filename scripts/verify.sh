#!/usr/bin/env bash
# Post-restart health check. Run after any reboot, `just up`, `just update`, or power loss.
# Verifies (in order of blast radius): external disks are mounted, containers are up and
# healthy, the VPN egress is up, and the public routes answer. Exits non-zero if any
# hard check fails, so it is safe to chain in scripts or cron.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/.env"
set +a

: "${MEDIA_ROOT:=/mnt/media}"
: "${BACKUP_MOUNT_POINT:=/mnt/backup-usb}"
: "${IMMICH_LIBRARY_ROOT:=/srv/data/immich/library}"
: "${LOCAL_DNS_ZONE:=michalklos.com}"

green() { printf '\033[32m%s\033[0m' "$1"; }
red()   { printf '\033[31m%s\033[0m' "$1"; }
yellow(){ printf '\033[33m%s\033[0m' "$1"; }

fails=0
warns=0
ok()   { printf '  [%s] %s\n' "$(green OK)"   "$1"; }
warn() { printf '  [%s] %s\n' "$(yellow WARN)" "$1"; warns=$((warns+1)); }
fail() { printf '  [%s] %s\n' "$(red FAIL)"  "$1"; fails=$((fails+1)); }

# --- 1. External disks -------------------------------------------------------
echo "1. External disks"
if mountpoint -q "$MEDIA_ROOT"; then
  ok "$MEDIA_ROOT mounted ($(df -h --output=size "$MEDIA_ROOT" | tail -1 | tr -d ' '))"
  [[ -d "$MEDIA_ROOT/video" && -d "$MEDIA_ROOT/downloads" ]] \
    && ok "media layout present (video/, downloads/)" \
    || warn "video/ or downloads/ missing under $MEDIA_ROOT"
else
  fail "$MEDIA_ROOT is NOT a mountpoint — containers would write to the SSD. Fix before starting the stack (sudo mount -a)."
fi

if mountpoint -q "$BACKUP_MOUNT_POINT"; then
  ok "$BACKUP_MOUNT_POINT mounted"
else
  warn "$BACKUP_MOUNT_POINT not mounted (backups will fail until remounted)"
fi

[[ -d "$IMMICH_LIBRARY_ROOT" ]] \
  && ok "Immich library present at $IMMICH_LIBRARY_ROOT (SSD)" \
  || warn "Immich library dir missing: $IMMICH_LIBRARY_ROOT"

# --- 2. Containers up & healthy ---------------------------------------------
echo "2. Containers"
containers=(
  traefik adguardhome tailscale
  homepage
  jellyfin homeassistant
  filebrowser samba
  immich_server immich_machine_learning immich_redis immich_postgres
  portainer stirling_pdf
  gluetun qbittorrent
  prowlarr radarr sonarr bazarr seerr
)
for c in "${containers[@]}"; do
  state=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "absent")
  if [[ "$state" != "running" ]]; then
    fail "$c is $state"
    continue
  fi
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null)
  case "$health" in
    healthy)  ok "$c (healthy)" ;;
    none)     ok "$c (running, no healthcheck)" ;;
    starting) warn "$c health: starting (still coming up)" ;;
    *)        fail "$c health: $health" ;;
  esac
done

# --- 3. VPN egress for the download stack -----------------------------------
echo "3. VPN egress (gluetun)"
if [[ "$(docker inspect --format '{{.State.Status}}' gluetun 2>/dev/null || echo absent)" == "running" ]]; then
  vpn_ip=$(docker exec gluetun sh -c 'wget -qO- --timeout=8 https://ipinfo.io/ip' 2>/dev/null | tr -d '[:space:]')
  if [[ -n "$vpn_ip" ]]; then
    ok "qBittorrent egress IP: $vpn_ip (verify this is the VPN, not your home IP)"
  else
    fail "could not read public IP through gluetun — VPN may be down (qBittorrent has no network)"
  fi
else
  fail "gluetun not running — qBittorrent has no network"
fi

# --- 4. Public routes (Traefik + cert + DNS) --------------------------------
echo "4. Public routes"
route_hosts=(
  "${JELLYFIN_HOST:-jellyfin.$LOCAL_DNS_ZONE}"
  "${IMMICH_HOST:-immich.$LOCAL_DNS_ZONE}"
  "${HOMEPAGE_HOST:-home.$LOCAL_DNS_ZONE}"
  "${RADARR_HOST:-radarr.$LOCAL_DNS_ZONE}"
  "${SONARR_HOST:-sonarr.$LOCAL_DNS_ZONE}"
  "${QBITTORRENT_HOST:-qbit.$LOCAL_DNS_ZONE}"
)
for h in "${route_hosts[@]}"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://$h" 2>/dev/null || echo 000)
  case "$code" in
    200|301|302|401|403) ok "$h -> $code" ;;
    000)                 fail "$h -> no response (DNS, Traefik, or cert problem)" ;;
    502|503|504)         fail "$h -> $code (route up but backend container is down)" ;;
    *)                   warn "$h -> $code" ;;
  esac
done

# --- Summary -----------------------------------------------------------------
echo
if (( fails == 0 && warns == 0 )); then
  echo "$(green "All checks passed.")"
elif (( fails == 0 )); then
  echo "$(yellow "Passed with $warns warning(s).")"
else
  echo "$(red "$fails failure(s), $warns warning(s).") Investigate with: just logs <service>"
fi
exit $(( fails > 0 ? 1 : 0 ))
