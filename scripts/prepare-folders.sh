#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cp -n "$ROOT_DIR/env/.env.example" "$ROOT_DIR/env/.env" || true
set -a
source "$ROOT_DIR/env/.env"
set +a

sudo mkdir -p \
  "$BASE_DIR" \
  "$BASE_DIR/homeassistant/config" \
  "$BASE_DIR/tailscale/state" \
  "$BASE_DIR/samba" \
  "$MEDIA_DIR/video" \
  "$MEDIA_DIR/immich/library"

if [[ ! -f "$BASE_DIR/samba/smb.conf" ]]; then
cat <<SMB | sudo tee "$BASE_DIR/samba/smb.conf" >/dev/null
[global]
   workgroup = WORKGROUP
   server string = HomeLab Samba Server
   map to guest = Bad User
   log file = /var/log/samba/log.%m
   max log size = 1000
   server role = standalone server
   obey pam restrictions = yes
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\\snew\\s*password:* %n\\n *Retype\\snew\\s*password:* %n\\n *password\\supdated\\ssuccessfully* .
   pam password change = yes
   usershare allow guests = yes

[media]
   path = /storage
   browseable = yes
   read only = no
   guest ok = no
   create mask = 0664
   directory mask = 0775
SMB
fi

echo "Folders are ready. Fill in passwords in env/.env and edit smb.conf if needed."
