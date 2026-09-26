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
    │    ├── z2m.michalklos.com       (Zigbee2MQTT)            │
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
    │                                                          │
    │  [SLZB-MR5U]  Zigbee radio ── tcp ──→ Zigbee2MQTT → MQTT │
    │               Thread border router ←→ Matter server      │
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
| Zigbee2MQTT | `z2m.michalklos.com` | Zigbee devices via the SLZB-MR5U |
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
| Mosquitto | MQTT broker between Zigbee2MQTT and Home Assistant, loopback-only (`127.0.0.1:1883`) |
| Matter Server | Matter controller for Home Assistant (`ws://localhost:5580/ws`), host networking |

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
just diff-config       # show what differs between repo and runtime configs
just sync-config       # repo -> runtime, then restart affected containers
just pull-config       # runtime -> repo (snapshot what the apps wrote)
```

`sync-config` and `pull-config` overwrite in opposite directions, so both run
`diff-config` first and ask for confirmation before copying anything. Set
`CONFIRM=yes` to skip the prompt in scripts.

Some apps rewrite their own config at runtime — AdGuard Home on every web UI
change, qBittorrent and Home Assistant likewise — so the runtime copy drifts
ahead of the repo. Always read the diff before answering the prompt; `pull-config`
is how you capture those changes back. Home Assistant's `automations.yaml`,
`scenes.yaml` and `scripts.yaml` are pull-only and never overwritten.

Run both with `sudo`, or answer the password prompt: the runtime
`AdGuardHome.yaml` is root-owned.

### Updating apps on the LG TV

The TV is cut off from LG's firmware, download and store servers by the
**LG TV — lockdown** blocklist. To install or update apps (or firmware): AdGuard
Home → Filters → DNS blocklists → untick **LG TV — lockdown**, do the update,
then tick it again. **LG TV — always blocked** stays on throughout. A forgotten
re-tick shows up in `just diff-config` as `enabled: false`.

## Stack

- **OS:** Ubuntu Server 24.04 LTS
- **Proxy:** Traefik v3.6 — HTTPS via Let's Encrypt DNS-01 (Cloudflare)
- **DNS:** AdGuard Home — local rewrite `*.michalklos.com → 192.168.10.10`, Cloudflare upstreams with Quad9 fallback, HaGeZi Pro + Threat Intelligence Feeds, LG TV lockdown lists
- **Remote access:** Tailscale (VPN)
- **Media stack:** Prowlarr, Radarr, Sonarr, Bazarr, Seerr — qBittorrent behind Gluetun (NordVPN WireGuard)
- **Smart home:** Home Assistant, Zigbee2MQTT + Mosquitto, Matter server; SMLIGHT SLZB-MR5U as Zigbee coordinator and Thread border router over Ethernet
- **Hardware acceleration:** Intel Quick Sync / VA-API + OpenVINO via `/dev/dri`
- **Backups:** restic → USB disk, weekly cron
