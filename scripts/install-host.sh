#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/install-host.sh"
  exit 1
fi

apt-get update
apt-get install -y \
  ca-certificates curl gnupg lsb-release jq git htop tmux smartmontools \
  avahi-daemon dnsmasq cifs-utils nfs-common restic rsync cron ufw \
  lm-sensors intel-media-va-driver-non-free vainfo

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker

ufw allow 22/tcp
ufw allow 53/tcp
ufw allow 53/udp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 445/tcp
# Home Assistant runs on host network; allow Docker containers (172.16/12) and LAN to reach it
ufw allow from 172.16.0.0/12 to any port 8123 proto tcp
ufw allow from 192.168.0.0/16 to any port 8123 proto tcp
ufw --force enable

echo "Host is ready. Next: fill in env/.env and run prepare-folders.sh"
