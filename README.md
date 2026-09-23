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
    │    ├── ha.michalklos.com        (Home Assistant)         │
    │    ├── dns.michalklos.com       (AdGuard Home)           │
    │    ├── files.michalklos.com     (FileBrowser)            │
    │    ├── pdf.michalklos.com       (Stirling PDF)           │
    │    ├── portainer.michalklos.com (Portainer)              │
    │    ├── seerr.michalklos.com     (Seerr)                  │
    │    ├── qbit.michalklos.com      (qBittorrent — via VPN)  │
    │    ├── prowlarr.michalklos.com  (Prowlarr)               │
    │    ├── radarr.michalklos.com    (Radarr)                 │
    │    ├── sonarr.michalklos.com    (Sonarr)                 │
    │    ├── bazarr.michalklos.com    (Bazarr)                 │
    │    └── traefik.michalklos.com   (Traefik dashboard)      │
    │                                                          │
    │  [Samba :445]  ←  LAN file shares                        │
    └──────────────────────────────────────────────────────────┘
    │
    └─── Tailscale VPN  (remote access to all services)
```

## Services

| Service | URL | Purpose |
|---|---|---|
| Homepage | `home.michalklos.com` | Dashboard |
| Jellyfin | `jellyfin.michalklos.com` | Media streaming (Intel QSV) |
| Immich | `immich.michalklos.com` | Photo management (OpenVINO) |
| Home Assistant | `ha.michalklos.com` | Home automation |
| AdGuard Home | `dns.michalklos.com` | DNS + ad blocking |
| FileBrowser | `files.michalklos.com` | Web file manager |
| Stirling PDF | `pdf.michalklos.com` | PDF tools |
| Portainer | `portainer.michalklos.com` | Docker container management |
| Seerr | `seerr.michalklos.com` | Media requests |
| qBittorrent | `qbit.michalklos.com` | Torrent client — all traffic via Gluetun |
| Prowlarr | `prowlarr.michalklos.com` | Indexer manager |
| Radarr | `radarr.michalklos.com` | Movie library |
| Sonarr | `sonarr.michalklos.com` | TV library |
| Bazarr | `bazarr.michalklos.com` | Subtitles |
| Traefik | `traefik.michalklos.com` | Reverse proxy dashboard |
| Samba | LAN port 445 | File shares |

No web UI of their own:

| Service | Purpose |
|---|---|
| Gluetun | NordVPN WireGuard tunnel — qBittorrent runs inside its network namespace |
| Recyclarr | Syncs TRaSH Guides quality profiles into Radarr and Sonarr |
| Tailscale | Mesh VPN for remote access, advertises `192.168.10.0/24` |
| Immich Postgres / Redis / ML | Immich's database, cache, and OpenVINO inference |

## Quick start

```bash
git clone https://github.com/klosmichal/homelab.git ~/homelab
cd ~/homelab
just init-env
# edit .env with your secrets, then:
just up
```

Full step-by-step instructions: [`docs/INSTALL.md`](docs/INSTALL.md)

## Daily operations

```bash
just up                # start core stack
just stop              # stop everything
just update            # pull new images and restart
just ps                # container status
just logs              # follow all logs
just backup            # run restic backup now
just check             # smoke test all containers
just verify            # full post-restart verification
just sync-config       # copy configs from repo to runtime, restart affected
```

`sync-config` needs `sudo` — the runtime config files are root-owned.

## Stack

- **OS:** Ubuntu Server 24.04 LTS
- **Proxy:** Traefik v3.6 — HTTPS via Let's Encrypt DNS-01 (Cloudflare)
- **DNS:** AdGuard Home — local rewrite `*.michalklos.com → 192.168.10.10`, Cloudflare upstreams with Quad9 fallback
- **Remote access:** Tailscale (VPN)
- **Media stack:** Prowlarr, Radarr, Sonarr, Bazarr, Seerr — qBittorrent behind Gluetun (NordVPN WireGuard)
- **Hardware acceleration:** Intel Quick Sync / VA-API + OpenVINO via `/dev/dri`
- **Backups:** restic → USB disk, weekly cron
