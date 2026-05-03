# Installation guide

Complete from-scratch setup for the homelab stack on MSI Cubi N ADL S-226BEU (Intel N200, 16 GB RAM).

---

## 1. Install Ubuntu Server 24.04 LTS

1. Boot the installer, select **Ubuntu Server (minimized)**.
2. Enable OpenSSH during installation.
3. After first boot, update the system:
   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```

---

## 2. Configure a static IP

Either set a DHCP reservation in your router (simplest), or configure a static address with Netplan. A ready-to-adapt example is in `config/netplan/01-cubi-static.yaml.example`.

```bash
# find your interface name
ip link

# copy and edit the example
sudo cp config/netplan/01-cubi-static.yaml.example /etc/netplan/01-cubi-static.yaml
sudo nano /etc/netplan/01-cubi-static.yaml   # replace interface name if needed

sudo netplan try && sudo netplan apply
```

Target: `192.168.10.10/24`, gateway `192.168.10.1`.

---

## 3. Clone the repository

```bash
git clone https://github.com/klosmichal/homelab.git ~/homelab
cd ~/homelab
cp env/env.production.example env/.env
```

---

## 4. Set up Cloudflare

You need a domain on Cloudflare for HTTPS certificates (DNS-01 challenge) and the optional public Vaultwarden tunnel.

### 4a. Point your domain to Cloudflare nameservers

In your domain registrar's control panel, replace the nameservers with the two Cloudflare assigns (shown in Cloudflare dashboard → your domain → DNS → Nameservers). Wait for propagation.

### 4b. Create a Cloudflare API token

Cloudflare dashboard → My Profile → API Tokens → **Create Token** → use the *Edit zone DNS* template, scope it to your domain. Copy the token — you only see it once.

---

## 5. Edit `env/.env`

Open `~/homelab/env/.env` and fill in all values:

| Variable | Description |
|---|---|
| `CF_DNS_API_TOKEN` | Cloudflare API token from step 4b |
| `ACME_EMAIL` | Your email for Let's Encrypt notifications |
| `CLOUDFLARE_TUNNEL_TOKEN` | Tunnel token from step 12 (fill in later) |
| `IMMICH_DB_PASSWORD` | Strong random password |
| `VAULTWARDEN_ADMIN_TOKEN` | Strong random token (`openssl rand -base64 48`) |
| `RESTIC_PASSWORD` | Strong random passphrase for backup encryption |
| `SAMBA_PASSWORD` | Samba share password |
| `TAILSCALE_AUTHKEY` | Optional — leave empty to authenticate manually |

All `*_HOST` variables are pre-set to `*.michalklos.com`. Change the domain if yours differs.

---

## 6. Create the Traefik basic auth file

The Traefik dashboard is protected by HTTP basic auth. Generate a hashed password with `htpasswd`:

```bash
sudo apt install -y apache2-utils
htpasswd -nb admin YOUR_PASSWORD > ~/homelab/env/traefik-users
```

Or without `apache2-utils`:

```bash
docker run --rm httpd:2 htpasswd -nb admin YOUR_PASSWORD > ~/homelab/env/traefik-users
```

The compose file mounts `env/traefik-users` into the Traefik container.

---

## 7. Mount the backup disk

```bash
lsblk -f    # find your USB disk UUID

sudo mkdir -p /mnt/backup-usb

# add to /etc/fstab:
echo 'UUID=YOUR-UUID /mnt/backup-usb ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

sudo mount -a
```

---

## 8. Prepare the host

Installs Docker Engine, UFW firewall rules, Intel GPU drivers, and tools:

```bash
sudo bash scripts/install-host.sh
```

---

## 9. Prepare data directories and AdGuard config

Creates all required directories under `/srv/homelab` and `/srv/data`, and deploys the pre-configured `AdGuardHome.yaml` (with the `*.michalklos.com` DNS rewrite):

```bash
bash scripts/prepare-folders.sh
```

---

## 10. Start the stack

```bash
cd ~/homelab
just up
```

Watch startup:
```bash
just logs
```

All containers should reach `healthy` or `running` within ~60 seconds. Check with:
```bash
just ps
```

---

## 11. Configure AdGuard Home

1. On first launch AdGuard Home needs an admin user. Connect to the homelab and run:
   ```bash
   docker exec -it adguardhome /opt/adguardhome/AdGuardHome -c /opt/adguardhome/conf/AdGuardHome.yaml --web-addr 0.0.0.0:3000
   ```
   Actually, just open `http://192.168.10.10:3000` directly (bypassing DNS since it isn't set up yet) and follow the setup wizard. The DNS rewrite for `*.michalklos.com → 192.168.10.10` is already in the config — you only need to create an admin password.

2. Verify the rewrite is active: AdGuard Home → Filters → DNS rewrites — you should see `*.michalklos.com → 192.168.10.10`.

---

## 12. Configure your router to use AdGuard Home as DNS

In your router's DHCP settings, set the **primary DNS server** to `192.168.10.10`. This makes all devices on your network resolve `*.michalklos.com` locally.

After saving, reconnect your devices to pick up the new DNS (or wait for DHCP lease renewal).

At this point `https://jellyfin.michalklos.com` should load in your browser with a valid Let's Encrypt certificate (Traefik requests it automatically on first access — allow up to a minute).

---

## 13. Configure Tailscale

Tailscale provides secure remote access to all services without exposing ports publicly.

If you left `TAILSCALE_AUTHKEY` empty, authenticate manually:
```bash
docker exec -it tailscale tailscale up
```

Follow the printed URL to approve the device in the Tailscale admin console. Install the Tailscale app on your phone and laptop to access the homelab remotely.

---

## 14. Set up the Cloudflare Tunnel (Vaultwarden public access)

This makes `vault.michalklos.com` reachable from anywhere without Tailscale.

1. Go to [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → Networks → Tunnels → **Create a tunnel** → Cloudflared.
2. Name it (e.g. `homelab`) and save.
3. Copy the tunnel token shown on the next screen.
4. Add it to `~/homelab/env/.env`:
   ```
   CLOUDFLARE_TUNNEL_TOKEN=eyJ...
   ```
5. On the **Public Hostnames** tab, add:
   - Subdomain: `vault`, Domain: `michalklos.com`, Type: `HTTPS`, URL: `traefik:443`
6. Save the tunnel.
7. Start the cloudflared container:
   ```bash
   cd ~/homelab && just up-cloudflared
   ```

Vaultwarden will now be reachable at `https://vault.michalklos.com` from anywhere.

---

## 15. First-time service configuration

### Jellyfin
Open `https://jellyfin.michalklos.com` → follow the setup wizard → in **Dashboard → Playback → Transcoding**, enable hardware acceleration: **Intel QuickSync (QSV)** or **Video Acceleration API (VAAPI)**, device `/dev/dri/renderD128`.

### Immich
Open `https://immich.michalklos.com` → create admin account. Hardware ML acceleration (OpenVINO) is pre-configured via the `immich-machine-learning` container.

### Home Assistant
Home Assistant runs in `network_mode: host` so it can access Bluetooth, mDNS, and other LAN protocols. Because of this it can't join the Docker `proxy` network, so Traefik reaches it via `host.docker.internal` (mapped to the Docker bridge gateway via `extra_hosts: host-gateway` on the Traefik service) rather than by container name.

`configuration.yaml` must trust the Docker proxy subnet as a reverse proxy — otherwise HA rejects forwarded headers. The relevant section (already in place):

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - 192.168.10.10
    - 172.18.0.0/16   # Docker proxy network
```

If you ever recreate the stack and the `proxy` network gets a different subnet, update this value and restart HA (`docker restart homeassistant`).

Open `http://192.168.10.10:8123` for first-time setup (before DNS is ready), or `https://ha.michalklos.com` once DNS is working.

### Vaultwarden
Open `https://vault.michalklos.com/admin` and enter your `VAULTWARDEN_ADMIN_TOKEN` to access the admin panel. Disable signups after creating your account: set `VAULTWARDEN_SIGNUPS_ALLOWED=false` in `.env` and `just up`.

### Homepage
Drop YAML widget configs into `${APPDATA_ROOT}/homepage/config/` (mapped to `/app/config` in the container). See the [Homepage docs](https://gethomepage.dev).

---

## 16. Schedule weekly backups

```bash
crontab -e
```

Add:
```
0 3 * * 0 /bin/bash /home/mklos/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

This runs every Sunday at 03:00. The script dumps the Immich PostgreSQL database and runs `restic backup` with retention (8 weekly, 6 monthly snapshots).

---

## 17. Ongoing updates

```bash
cd ~/homelab
just update          # pull latest images, recreate containers
sudo apt update && sudo apt upgrade -y   # host OS
```

Run every 2–4 weeks.
