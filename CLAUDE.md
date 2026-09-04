# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Self-hosted homelab infrastructure for an MSI Cubi N ADL S-226BEU mini PC (Intel N200). Single `docker-compose.yml` manages all services; everything is driven by a single `.env` file.

## Common commands

All operations use `just` (task runner). Run from repo root:

```bash
just init-env      # Copy env.production.example → .env (first-time setup)
just up            # Start core stack
just stop          # Stop all containers
just update        # Pull latest images and restart
just ps            # Container status
just logs          # Follow all logs
just backup        # Run restic backup manually
just check         # Run healthcheck-smoke.sh
just sync-config   # Copy configs from repo to runtime locations and restart affected containers
```

Direct docker compose (when not using just):
```bash
docker compose up -d
```

Scripts are in `scripts/` — run directly as `sudo bash scripts/install-host.sh`, etc.

## Architecture

### Single-file stack

`docker-compose.yml` defines all ~18 services. Two networks:
- `proxy` — services exposed via Traefik (have `traefik.*` labels)
- `internal` — databases and caches only (never touch Traefik)

No optional profiles — all services run as part of the core stack.

### Networking model

All services resolve via DNS names (`*.michalklos.com`), never by IP. Traefik handles TLS termination and routing on ports 80/443 with Let's Encrypt DNS-01 certs via Cloudflare. Local DNS is provided by AdGuard Home running as a Docker container — config at `config/adguardhome/AdGuardHome.yaml`. Router DHCP hands out `192.168.10.10` as primary DNS and `1.1.1.1` as fallback.

AdGuard Home provides:
- DNS rewrite: `*.michalklos.com` → `192.168.10.10`
- Ad/tracker blocking via AdGuard DNS filter, OISD Big, and HaGeZi Multi PRO lists

Remote access is Tailscale by default (mesh VPN, no port forwarding). Cloudflare Tunnel is optional for Vaultwarden only — profile `cloudflared` in `docker-compose.yml`.

Home Assistant and Tailscale use host networking; all other services use the bridge networks above.

### Configuration

- `env.production.example` — production values for this specific hardware
- `.env` — actual secrets (gitignored, never committed)
- `config/traefik/traefik-users.example` — htpasswd-format credentials for Traefik dashboard

Key env variable groups:
- `HOST_*` — server identity and network (LAN IP: `192.168.10.10`)
- `*_ROOT` — filesystem mount points (`APPDATA_ROOT=/srv/homelab`, `MEDIA_ROOT=/srv/data`)
- `*_HOST` — service DNS names (`JELLYFIN_HOST=jellyfin.michalklos.com`, etc.)
- `PUID`/`PGID` — UID/GID for linuxserver.io containers (default `1000`)
- `TZ=Europe/Warsaw`

### Hardware integration

`/dev/dri` is mounted into Jellyfin and Immich ML containers for Intel Quick Sync / VA-API hardware transcoding and OpenVINO inference.

### Backup

`scripts/backup.sh` dumps the Immich PostgreSQL database, then runs `restic backup` to `/mnt/backup-usb/restic`. Scheduled via cron: `0 3 * * 0` (Sunday 3 AM). Retention: 8 weekly + 6 monthly snapshots.

## Key docs

- `docs/INSTALL.md` — full step-by-step deployment
- `docs/JELLYFIN-TV.md` — LG G4 playback settings and measured codec compatibility
