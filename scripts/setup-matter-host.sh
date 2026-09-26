#!/usr/bin/env bash
# Host settings the matter-server container needs. It runs on the host network,
# so UFW and the host kernel sit directly in the path of Matter traffic.
# Idempotent: install-host.sh calls it, and it is safe to re-run on its own.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/setup-matter-host.sh"
  exit 1
fi

LAN_IF=$(ip route show default | awk '{print $5; exit}')
if [[ -z "$LAN_IF" ]]; then
  echo "No default route — cannot tell which interface is the LAN." >&2
  exit 1
fi

# Thread devices reach the controller from the border router's ULA prefix, and
# Matter nodes pick their own UDP ports, so filter by source prefix, never port.
ufw allow in on "$LAN_IF" from fd00::/8 comment 'Matter/Thread ULA'
ufw allow in on "$LAN_IF" from fe80::/10 comment 'Matter link-local'

# UFW's conntrack forgets a UDP flow after 120 s, but battery (sleepy) Matter
# devices report every few minutes, so their reports get dropped. Load the
# module at boot so the sysctl exists when systemd-sysctl applies it.
echo nf_conntrack > /etc/modules-load.d/matter.conf
modprobe nf_conntrack

# The Matter server pings devices as an unprivileged user; Ubuntu's default
# ping_group_range ("1 0") allows nobody.
cat > /etc/sysctl.d/99-matter.conf <<'EOF'
net.netfilter.nf_conntrack_udp_timeout_stream = 3600
net.ipv4.ping_group_range = 0 2147483647
EOF
sysctl -p /etc/sysctl.d/99-matter.conf

# Thread routing only works while IPv6 forwarding is off: with it on, the
# kernel stops probing border routers and dead routes linger for up to 30 min.
if [[ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" != "0" ]]; then
  echo "WARNING: net.ipv6.conf.all.forwarding is on — Thread routes will be unreliable." >&2
fi

echo "Matter host settings applied on $LAN_IF."
