# Homelab — MSI Cubi N ADL S-226BEU

Self-hosted media, photos, home automation, and productivity services on an Intel N200 mini PC running Ubuntu Server 24.04 LTS + Docker Compose.

## Architecture

```
Your device
    │
    ├─── LAN ──────────────────────────────────────────────────┐
    │                                                          │
    │  [AdGuard Home :53]  ←  *.michalklos.com → 192.168.10.10│
    │                                                          │
    │  [Traefik :80/:443]  ←  Let's Encrypt via Cloudflare DNS│
    │    ├── home.michalklos.com      (Homepage)               │
    │    ├── jellyfin.michalklos.com  (Jellyfin)               │
    │    ├── immich.michalklos.com    (Immich)                 │
    │    ├── vault.michalklos.com     (Vaultwarden)            │
    │    ├── ha.michalklos.com        (Home Assistant)         │
    │    ├── kuma.michalklos.com      (Uptime Kuma)            │
    │    ├── dns.michalklos.com       (AdGuard Home)           │
    │    ├── pdf.michalklos.com       (Stirling PDF)           │
    │    ├── files.michalklos.com     (FileBrowser)            │
    │    └── traefik.michalklos.com   (Traefik dashboard)      │
    │                                                          │
    └──────────────────────────────────────────────────────────┘
    │
    ├─── Tailscale VPN  (remote access to all services)
    │
    └─── Cloudflare Tunnel  (vault.michalklos.com — public, no VPN needed)
```

## Services

| Service | URL | Purpose |
|---|---|---|
| Homepage | `home.michalklos.com` | Dashboard |
| Jellyfin | `jellyfin.michalklos.com` | Media streaming (Intel QSV) |
| Immich | `immich.michalklos.com` | Photo management (OpenVINO) |
| Vaultwarden | `vault.michalklos.com` | Password manager — also public via Cloudflare Tunnel |
| Home Assistant | `ha.michalklos.com` | Home automation |
| AdGuard Home | `dns.michalklos.com` | DNS + ad blocking |
| Uptime Kuma | `kuma.michalklos.com` | Monitoring |
| Stirling PDF | `pdf.michalklos.com` | PDF tools |
| FileBrowser | `files.michalklos.com` | Web file manager |
| Traefik | `traefik.michalklos.com` | Reverse proxy dashboard |
| Samba | LAN port 445 | File shares |

Optional profiles: `dozzle` (log viewer), `cloudflared` (Vaultwarden public tunnel).

## Quick start

```bash
git clone https://github.com/klosmichal/homelab.git ~/homelab
cd ~/homelab
cp env/env.production.example env/.env
# edit env/.env with your secrets, then:
just up
```

Full step-by-step instructions: [`docs/INSTALL.md`](docs/INSTALL.md)

## Daily operations

```bash
just up                # start core stack
just up-dozzle         # + Dozzle log viewer
just up-cloudflared    # + Cloudflare Tunnel (Vaultwarden public)
just stop              # stop everything
just update            # pull new images and restart
just ps                # container status
just logs              # follow all logs
just backup            # run restic backup now
just check             # smoke test all containers
```

## Stack

- **OS:** Ubuntu Server 24.04 LTS
- **Proxy:** Traefik v3.6 — HTTPS via Let's Encrypt DNS-01 (Cloudflare)
- **DNS:** AdGuard Home — local rewrite `*.michalklos.com → 192.168.10.10`
- **Remote access:** Tailscale (VPN) + Cloudflare Tunnel (Vaultwarden only)
- **Hardware acceleration:** Intel Quick Sync / VA-API + OpenVINO via `/dev/dri`
- **Backups:** restic → USB disk, weekly cron
