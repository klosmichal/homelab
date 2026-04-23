#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp --update=none "$ROOT_DIR/env/.env.example" "$ROOT_DIR/env/.env" 2>/dev/null || true
set -a
source "$ROOT_DIR/env/.env"
set +a

sudo mkdir -p \
  "$APPDATA_ROOT" \
  "$APPDATA_ROOT/homeassistant/config" \
  "$APPDATA_ROOT/tailscale/state" \
  "$APPDATA_ROOT/samba" \
  "$MEDIA_ROOT/video" \
  "$MEDIA_ROOT/immich/library"

if [[ ! -f "$APPDATA_ROOT/samba/smb.conf" ]]; then
cat <<SMB | sudo tee "$APPDATA_ROOT/samba/smb.conf" >/dev/null
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
