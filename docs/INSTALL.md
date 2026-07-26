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

Set a DHCP reservation in your router for the server's MAC address, targeting `192.168.10.10`.

---

## 3. Clone the repository

```bash
git clone https://github.com/klosmichal/homelab.git ~/homelab
cd ~/homelab
cp env.production.example .env
```

---

## 4. Set up Cloudflare

You need a domain on Cloudflare for HTTPS certificates (DNS-01 challenge) and the optional public Vaultwarden tunnel.

### 4a. Point your domain to Cloudflare nameservers

In your domain registrar's control panel, replace the nameservers with the two Cloudflare assigns (shown in Cloudflare dashboard → your domain → DNS → Nameservers). Wait for propagation.

### 4b. Create a Cloudflare API token

Cloudflare dashboard → My Profile → API Tokens → **Create Token** → use the *Edit zone DNS* template, scope it to your domain. Copy the token — you only see it once.

### 4c. Get your NordVPN WireGuard private key (for the arr stack VPN)

1. Go to **my.nordaccount.com** → **Services** → **NordVPN** → scroll to **Access token** → **Generate new token** (choose "doesn't expire").
2. Run the following to extract the WireGuard private key:
   ```bash
   curl -s -u token:YOUR_ACCESS_TOKEN \
     https://api.nordvpn.com/v1/users/services/credentials | jq -r .nordlynx_private_key
   ```
   Copy the output — this is your `NORDVPN_PRIVATE_KEY`.

---

## 5. Edit `.env`

Open `~/homelab/.env` and fill in all values:

| Variable | Description |
|---|---|
| `CF_DNS_API_TOKEN` | Cloudflare API token from step 4b |
| `ACME_EMAIL` | Your email for Let's Encrypt notifications |
| `IMMICH_DB_PASSWORD` | Strong random password |
| `VAULTWARDEN_ADMIN_TOKEN` | Strong random token (`openssl rand -base64 48`) |
| `RESTIC_PASSWORD` | Strong random passphrase for backup encryption |
| `SAMBA_PASSWORD` | Samba share password |
| `TAILSCALE_AUTHKEY` | Optional — leave empty to authenticate manually |
| `NORDVPN_PRIVATE_KEY` | WireGuard private key from step 4c |

All `*_HOST` variables are pre-set to `*.michalklos.com`. Change the domain if differs.

---

## 6. Create the Traefik basic auth file

The Traefik dashboard is protected by HTTP basic auth. Generate a hashed password with `htpasswd`:

```bash
sudo apt install -y apache2-utils
htpasswd -nb admin YOUR_PASSWORD > ~/homelab/config/traefik/traefik-users
```

Or without `apache2-utils`:

```bash
docker run --rm httpd:2 htpasswd -nb admin YOUR_PASSWORD > ~/homelab/config/traefik/traefik-users
```

The compose file mounts `env/traefik-users` into the Traefik container.

---

## 7. Mount the disks

This host uses three storage areas:

| Mount | Device | Holds |
|---|---|---|
| `/` (NVMe SSD) | internal | OS, `${APPDATA_ROOT}` (`/srv/homelab`), and the Immich library (`${IMMICH_LIBRARY_ROOT}` = `/srv/data/immich/library`) |
| `/mnt/media` (8 TB USB HDD) | external | `${MEDIA_ROOT}` — Jellyfin library (`video/`) + qBittorrent/*arr downloads (`downloads/`) |
| `/mnt/backup-usb` (USB HDD) | external | restic backup repository |

Jellyfin's library and the download pipeline live together on `/mnt/media` so Radarr/Sonarr can **hardlink** imports (instant, no double disk usage). Immich stays on the SSD, kept separate via its own `IMMICH_LIBRARY_ROOT` variable so it isn't pulled onto the media HDD.

### 7a. Media disk (8 TB HDD → `/mnt/media`)

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL    # confirm the device (e.g. /dev/sda) and size

# Partition + format (DESTROYS the disk — verify the device first):
sudo parted /dev/sda mklabel gpt
sudo parted -a optimal /dev/sda mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L media -m 0 /dev/sda1     # -m 0: no reserved space on a media disk

sudo mkdir -p /mnt/media
sudo blkid /dev/sda1                        # copy the UUID

# add to /etc/fstab (use the UUID above):
echo 'UUID=YOUR-MEDIA-UUID /mnt/media ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

sudo mount -a
df -h /mnt/media                            # confirm mounted at full size
```

`nofail` lets the host boot if the disk is disconnected. Trade-off: if the disk is missing at boot, `/mnt/media` is an empty folder on the SSD and containers see an empty library — after any reboot, confirm `df -h /mnt/media` before trusting it.

### 7b. Backup disk (`/mnt/backup-usb`)

```bash
lsblk -f    # find your backup USB disk UUID

sudo mkdir -p /mnt/backup-usb

# add to /etc/fstab:
echo 'UUID=YOUR-BACKUP-UUID /mnt/backup-usb ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

sudo mount -a
```

---

## 8. Prepare the host

Installs Docker Engine, UFW firewall rules, Intel GPU drivers, and tools:

```bash
sudo bash scripts/install-host.sh
```

---

## 9. Prepare data directories and configs

Creates all required directories — app data under `/srv/homelab`, the media library + downloads under `${MEDIA_ROOT}` (`/mnt/media`), and the Immich library under `${IMMICH_LIBRARY_ROOT}` (`/srv/data/immich/library`) — and seeds initial configs for AdGuard Home, Samba, and qBittorrent. Idempotent — safe to re-run after adding new services:

```bash
bash scripts/prepare-folders.sh
```

To re-apply managed configs to running containers (AdGuard Home, Samba, qBittorrent) without recreating them:

```bash
just sync-config
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

### 13a. Authenticate the node

If you left `TAILSCALE_AUTHKEY` empty, authenticate manually:
```bash
docker exec -it tailscale tailscale up
```

Follow the printed URL to approve the device in the Tailscale admin console.

### 13b. Approve subnet routes

The container advertises `192.168.10.0/24` as a subnet route so remote clients can reach LAN services (including AdGuard Home's DNS at `192.168.10.10`).

In the [Tailscale admin console](https://login.tailscale.com/admin/machines):
1. Click the `cubi-homelab` machine → **Edit route settings**
2. Enable `192.168.10.0/24`

### 13c. Configure split DNS

This makes `*.michalklos.com` resolve correctly on remote devices without routing all traffic through the homelab.

In the [Tailscale admin console](https://login.tailscale.com/admin/dns):
1. Under **Nameservers** → **Add nameserver** → **Custom**
2. Enter `192.168.10.10` (AdGuard Home)
3. Check **Restrict to domain** and enter `michalklos.com`

Remote devices (mobile, laptop) will then query AdGuard Home for `*.michalklos.com` → get `192.168.10.10` → reach Traefik via the subnet route.

---

## 14. First-time service configuration

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

UFW must also allow port 8123 from Docker's private range and the LAN — this is handled by `install-host.sh`. If HA is unreachable through Traefik (504), check that these UFW rules are present:
```bash
sudo ufw status | grep 8123
# should show rules for 172.16.0.0/12 and 192.168.0.0/16
```

Open `http://192.168.10.10:8123` for first-time setup (before DNS is ready), or `https://ha.michalklos.com` once DNS is working.

### Homepage
The dashboard config lives in `config/homepage/` in the repo and is synced to `${APPDATA_ROOT}/homepage/config/` (mapped to `/app/config` in the container). See the [Homepage docs](https://gethomepage.dev).

Widget secrets (API keys, passwords) are **not** stored in `services.yaml`. Instead they are kept in `.env` and injected into the container as `HOMEPAGE_VAR_*` variables; `services.yaml` only references them via `{{HOMEPAGE_VAR_...}}` placeholders, which Homepage substitutes at runtime. To enable the widgets, fill in these values in `.env`:

| Variable | Where to get it |
|---|---|
| `ADGUARD_USERNAME` / `ADGUARD_PASSWORD` | Your AdGuard Home admin login |
| `IMMICH_API_KEY` | Immich → Account Settings → API Keys |
| `JELLYFIN_API_KEY` | Jellyfin → Dashboard → API Keys |
| `HOMEASSISTANT_TOKEN` | Home Assistant → Profile → Long-lived access tokens |
| `QBITTORRENT_USERNAME` / `QBITTORRENT_PASSWORD` | qBittorrent WebUI login |
| `SEERR_API_KEY` | Seerr → Settings → General → API Key |
| `PROWLARR_API_KEY` | Prowlarr → Settings → General |
| `RADARR_API_KEY` | Radarr → Settings → General |
| `SONARR_API_KEY` | Sonarr → Settings → General |
| `BAZARR_API_KEY` | Bazarr → Settings → General |
| `PORTAINER_API_KEY` | Portainer → Account Settings → Access Tokens |

After updating `.env`, recreate the container so it picks up the new environment: `docker compose up -d homepage`.

### Arr stack (Seerr, Radarr, Sonarr, Prowlarr, qBittorrent, Bazarr)

Configure in this order — each service's API key is needed by the next:

**0. qBittorrent** (`https://qbit.michalklos.com`)
- On first start a temporary password is printed to logs: `just logs qbittorrent | grep password`.
- Log in with `admin` + temp password, then immediately set a permanent password: **Tools → Options → Web UI → Authentication**.
- Do this **before** configuring Radarr/Sonarr — they store the password and will silently fail to add torrents if it changes later.
- Set the default save path to `/data/downloads/complete`: **Tools → Options → Downloads → Default Save Path**.
- Leave seeding limits disabled — Radarr/Sonarr remove torrents automatically after import (`removeCompletedDownloads` is enabled in both).

**1. Prowlarr** (`https://prowlarr.michalklos.com`)
- Create an admin account on first visit.
- Add indexers: Settings → Indexers → Add Indexer.
- Connect Radarr and Sonarr so indexers sync automatically: Settings → Apps → Add → Radarr (host: `radarr`, port: `7878`, API key from Radarr's Settings → General). Repeat for Sonarr (host: `sonarr`, port: `8989`).

**2. Radarr** (`https://radarr.michalklos.com`)
- Settings → Download Clients → Add → qBittorrent → Host: `gluetun`, Port: `8080`.
- Settings → Media Management → Root Folders → Add → `/data/video/movies`.
- Enable **Rename Movies** under Media Management.

**3. Sonarr** (`https://sonarr.michalklos.com`)
- Same as Radarr. Root folder: `/data/video/shows`.

**4. Bazarr** (`https://bazarr.michalklos.com`)
- Settings → Radarr → enable, host: `radarr`, port: `7878`, API key from Radarr.
- Settings → Sonarr → enable, host: `sonarr`, port: `8989`, API key from Sonarr.
- Settings → Languages → add profile: English (required), Polish (optional).
- Settings → Providers → add at least one subtitle provider (e.g. OpenSubtitles).

**5. Seerr** (`https://seerr.michalklos.com`)
- First-visit wizard: connect Jellyfin → host: `jellyfin`, port: `8096`.
- Add Radarr: host: `radarr`, port: `7878`, API key, default root folder `/data/video/movies`.
- Add Sonarr: host: `sonarr`, port: `8989`, API key, default root folder `/data/video/shows`.
- Create your admin account — this is the URL you share with household users.

**qBittorrent notes**
- On first start, a random WebUI password is printed to the container logs: `just logs qbittorrent | grep password`.
- The host header validation is disabled by the seeded config so Traefik proxying works out of the box.
- Set seeding limits to zero if you want downloads to stop seeding immediately: Tools → Options → BitTorrent → Seeding Limits → set ratio to `0`.

---

## 15. Schedule weekly backups

```bash
crontab -e
```

Add:
```
0 3 * * 0 /bin/bash /home/mklos/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

This runs every Sunday at 03:00. The script dumps the Immich PostgreSQL database and runs `restic backup` with retention (8 weekly, 6 monthly snapshots).

---

## 16. Verify services after a restart

Run this after any reboot, `just up`, `just update`, or power loss:

```bash
just verify
```

`scripts/verify.sh` checks, in order of blast radius:

1. **External disks mounted** — because the disks use `nofail`, the host boots even if a disk didn't come up, and containers would then write to an **empty folder on the SSD**. This is the first thing to confirm: `/mnt/media` and `/mnt/backup-usb` must be real mountpoints, and the media layout (`video/`, `downloads/`) must be present. A `FAIL` here means **do not start the stack** — fix the mount first (`sudo mount -a`; check the cable/enclosure and `sudo dmesg | grep sda`).
2. **Containers up & healthy** — every expected container is `running`; those with healthchecks report `healthy` (`starting` is a transient warning right after boot).
3. **VPN egress** — Gluetun is up and returns a public IP; qBittorrent has no network if Gluetun is down. Confirm the printed IP is the VPN's, not your home IP.
4. **Public routes** — each key `*.michalklos.com` host answers through Traefik with a valid cert. `200/301/302/401/403` are all fine; `000` is a DNS/Traefik/cert problem; `502/503/504` means the backing container is down.

The script exits non-zero if any hard check fails. Investigate failures with `just logs <service>`. For a quick container-only presence check, `just check` still runs the lightweight smoke test.

After a clean run, eyeball the essentials in a browser: Jellyfin plays a title (confirms `/mnt/media` is readable + hardware transcode), Immich loads photos (confirms the SSD library), and the Homepage dashboard shows green widgets.

---

## 17. Ongoing updates

```bash
cd ~/homelab
just update          # pull latest images, recreate containers
sudo apt update && sudo apt upgrade -y   # host OS
```

Run every 2–4 weeks.
