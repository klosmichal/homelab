# Step-by-step installation guide

## 1. Assumptions

- Mini PC: MSI Cubi N ADL S-226BEU with Intel N200 and Intel UHD Graphics.[web:2][web:3]
- Operating system: Ubuntu Server 24.04 LTS.
- Disk 1: system + service data.
- Disk 2: `restic` backup target over USB.

## 2. Install the operating system

1. Install Ubuntu Server 24.04 LTS.
2. Configure a static DHCP lease in the router for the mini PC.
3. Enable SSH during installation.
4. Log in and update the system:
   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```

## 3. Clone the repository

```bash
git clone <INSERT_YOUR_REPO_URL> homelab-msi-cubi
cd homelab-msi-cubi
cp env/env.production.example env/.env
```

## 4. Prepare the host

```bash
sudo bash scripts/install-host.sh
bash scripts/prepare-folders.sh
```

## 5. Edit environment variables

Edit `env/.env` and set the deployment-specific values:
- all passwords,
- service hostnames,
- data and backup paths,
- `TAILSCALE_AUTHKEY` if you want auto-join.

## 6. Mount the backup disk

1. Identify the disk UUID:
   ```bash
   lsblk -f
   ```
2. Add an entry to `/etc/fstab`, for example:
   ```fstab
   UUID=XXXX-XXXX /mnt/backup-usb ext4 defaults,nofail 0 2
   ```
3. Create the mount point and mount it:
   ```bash
   sudo mkdir -p /mnt/backup-usb
   sudo mount -a
   ```

## 7. Start services

Core stack only:
```bash
docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d
```

Core stack + Dozzle:
```bash
docker compose --profile dozzle --env-file ./env/.env -f ./compose/docker-compose.yml up -d
```

Core stack + Portainer:
```bash
docker compose --profile portainer --env-file ./env/.env -f ./compose/docker-compose.yml up -d
```

Core stack + both:
```bash
docker compose --profile dozzle --profile portainer --env-file ./env/.env -f ./compose/docker-compose.yml up -d
```

## 8. First configuration after startup

1. Open `https://home.home.arpa` and configure Homarr.
2. Open `http://<HA_IP>:8123` for Home Assistant, because it runs in `host` network mode.
3. Open `https://kuma.home.arpa` and add HTTP/TCP monitors for your services.
4. Configure Kuma notifications through `ntfy`, Telegram, or SMTP.[web:22][web:25]
5. Open Jellyfin and configure Intel VA-API / QSV hardware acceleration.
6. Open Immich and verify transcoding settings.
7. If Portainer is enabled, open `https://portainer.home.arpa` and configure the admin account.
8. If Dozzle is enabled, open `https://logs.home.arpa` and verify log access.

## 9. Configure local DNS

### Option A: router
The best option is to define local DNS records directly on the router if the firmware supports it.

### Option B: dnsmasq on the mini PC
Configure `dnsmasq` so that it resolves the local `home.arpa` zone, then point your router or clients to the mini PC as DNS.

Example `/etc/dnsmasq.d/homelab.conf`:
```conf
address=/traefik.home.arpa/192.168.10.10
address=/home.home.arpa/192.168.10.10
address=/immich.home.arpa/192.168.10.10
address=/jellyfin.home.arpa/192.168.10.10
address=/vault.home.arpa/192.168.10.10
address=/ha.home.arpa/192.168.10.10
address=/portainer.home.arpa/192.168.10.10
address=/logs.home.arpa/192.168.10.10
address=/kuma.home.arpa/192.168.10.10
address=/pdf.home.arpa/192.168.10.10
```

Then restart dnsmasq:
```bash
sudo systemctl restart dnsmasq
```

## 10. Weekly backup

Add a cron entry:
```bash
crontab -e
```

Entry:
```cron
0 3 * * 0 /bin/bash /path/to/homelab-msi-cubi/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

This runs a backup every Sunday at 03:00.

## 11. Tailscale

If you do not use `TAILSCALE_AUTHKEY`, authenticate manually:
```bash
docker exec -it tailscale tailscale up
```

Then use MagicDNS names or Tailscale IPs to access the machine remotely.

## 12. Test the stack

```bash
bash scripts/healthcheck-smoke.sh
```

## 13. Updates

Every 2 to 4 weeks:
```bash
docker compose --env-file ./env/.env -f ./compose/docker-compose.yml pull
docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d
```

Update the host system as well:
```bash
sudo apt update && sudo apt upgrade -y
```

## 14. Router configuration and network segmentation

Yes — **you should additionally configure the router**, because containerization alone does not solve network segmentation. TP-Link Guest Network can isolate guest clients from the local network, as long as you do not enable guest access to the local network.[page:1][web:32]

With two Archer BE230 routers in a mesh setup, the best practical layout is:
- **main / private network** — PCs, phones, TVs, laptops, server,
- **IoT / guest-like network** — washer, vacuum, low-trust smart devices,
- optionally a separate guest network if you often allow third-party devices into your Wi‑Fi.

### Where to place the mini PC

**Place the mini PC in the private network, not the IoT network.** The IoT segment should be treated as lower trust and limited to devices that need internet access but should not be able to scan or initiate connections freely to your server and computers.[web:38]

This also makes operations simpler: if the mini PC stays in the private network, it is easier to keep backups, Samba, and administrative panels outside the reach of untrusted smart devices.[web:38]

### What to configure on TP-Link

1. Keep the **main SSID** as the private network.
2. Enable **Guest Network** as the IoT network, preferably with 2.4 GHz support because many IoT devices still require it.[page:1]
3. **Do not enable** `Allow Guest to access my local network`, because that removes the separation between IoT and your private devices.[page:1][web:32]
4. If the firmware offers client isolation or Device Isolation, use it for the least trusted devices as an additional safeguard.[web:37]
5. Use separate strong passwords for the IoT and private networks.
6. Keep firmware updated on both mesh routers.[web:38]

### Limitations of this approach

On a typical consumer router, Guest Network provides **useful isolation**, but it is still not the same as full VLANs with dedicated firewall rules. The best-practice security model for IoT is a segment where devices can reach the internet but cannot initiate connections into the private network, while the private network may access IoT only when needed for control.[web:38]

In practice, the Archer BE230 will most likely implement this through Guest Network rather than through enterprise-style VLAN/ACL features. For a home setup that prioritizes simplicity and safety without replacing the entire network, that is still a very reasonable choice.[page:1][web:36]

### Service impact

- **Home Assistant**: keep it in the private network; some IoT integrations may still require exceptions or vendor cloud integration.
- **Samba, Portainer, Dozzle, Traefik, Uptime Kuma**: private network only, plus remote access through Tailscale.
- **Jellyfin, Immich**: private network; external access should usually go through Tailscale.
- **Vaultwarden**: private network, with optional public exposure only through Cloudflare Tunnel if you decide to add it later.[web:21][web:30]

### Recommended security model

- private network: your PCs, phones, TVs, mini PC,
- IoT network: smart appliances, vacuum, cloud-managed cameras, and other lower-trust devices,
- administrative access to the homelab only from the private network or through Tailscale,
- no public exposure of admin panels,
- optional Vaultwarden-only public exception later.


## 15. Optional local dnsmasq file deployment

A ready-to-adapt sample file is included in `config/dnsmasq/homelab.conf.example`. Copy it to `/etc/dnsmasq.d/homelab.conf`, adjust the IP addresses if needed, and restart the service.[web:97][web:100]

```bash
sudo cp config/dnsmasq/homelab.conf.example /etc/dnsmasq.d/homelab.conf
sudo systemctl restart dnsmasq
```

## 16. Optional just task runner

If you install `just`, you can use short operational commands such as `just up`, `just update`, and `just backup` instead of typing the full Docker Compose commands every time. This is purely for operator convenience.[web:96][web:99]


## 17. Optional static IP on Ubuntu with Netplan

If you prefer a fully static address on the mini PC instead of DHCP reservation, a ready-to-adapt Netplan file is included in `config/netplan/01-cubi-static.yaml.example`. Ubuntu Server 24.04 uses Netplan for network configuration, and a static address is a common approach for service hosts that must keep a stable LAN IP.[web:106][web:107]

1. Identify the actual interface name on your machine:
   ```bash
   ip link
   ```
2. Replace `enp1s0` in the example file if your interface name is different.
3. Copy the file into `/etc/netplan/`:
   ```bash
   sudo cp config/netplan/01-cubi-static.yaml.example /etc/netplan/01-cubi-static.yaml
   ```
4. Apply the configuration:
   ```bash
   sudo netplan try
   sudo netplan apply
   ```

The included example is already aligned to `192.168.10.10/24`, gateway `192.168.10.1`, and the local `home.arpa` search domain.[web:106][web:112]

## 18. Recommended Tailscale onboarding for this host

For a long-lived server, use a normal or pre-approved auth key rather than an ephemeral one. Tailscale documents ephemeral keys mainly for short-lived workloads, while reusable or pre-approved keys are a better fit for persistent servers.[web:111][web:113][web:116]

The safest workflow is:
- leave `TAILSCALE_AUTHKEY` empty for the first deployment,
- start the stack,
- run `docker exec -it tailscale tailscale up`,
- approve the device in Tailscale if needed,
- then decide later whether you want to automate re-provisioning with an auth key.
