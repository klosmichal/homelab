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

`docker-compose.yml` defines all 25 services. Two networks:
- `proxy` — services exposed via Traefik (have `traefik.*` labels)
- `internal` — databases, caches and the MQTT broker (never touch Traefik)

No optional profiles — all services run as part of the core stack.

### Networking model

All services resolve via DNS names (`*.michalklos.com`), never by IP. Traefik handles TLS termination and routing on ports 80/443 with Let's Encrypt DNS-01 certs via Cloudflare. Local DNS is provided by AdGuard Home running as a Docker container — config at `config/adguardhome/AdGuardHome.yaml`. Router DHCP hands out `192.168.10.10` as primary DNS and `1.1.1.1` as fallback.

AdGuard Home provides:
- DNS rewrite: `*.michalklos.com` → `192.168.10.10`
- Ad/tracker blocking via AdGuard DNS filter, HaGeZi Pro, and the MajkiIT / Polish Pi-hole lists
- Malware/phishing blocking via HaGeZi Threat Intelligence Feeds, HaGeZi Badware Hoster, and CERT Polska
- LG TV lockdown: two local lists in `config/adguardhome/userfilters/`, every rule scoped to the TV with `$client='192.168.10.12'`. `lg-tv-always.txt` (telemetry, ACR, ThinQ, network scanning) stays enabled; `lg-tv-lockdown.txt` (firmware, app downloads, store) is unticked in the web UI for an update and ticked again afterwards. `pl.nextlgsdp.com` must never be blocked: the TV sets its clock from it and apps fail without it. `config-sync` copies these files to `${APPDATA_ROOT}/adguardhome/work/data/userfilters/`, which AdGuard reads as `/opt/adguardhome/work/data/userfilters/`
- Upstreams: Cloudflare `1.1.1.1`/`1.0.0.1` queried in `parallel` mode, with Quad9 as `fallback_dns`

Note that AdGuard rewrites `AdGuardHome.yaml` itself whenever settings change in its web UI, so the runtime file can drift ahead of the repo copy. Diff before running `sync-config`, or UI changes are lost.

Remote access is Tailscale only (mesh VPN, no port forwarding).

Home Assistant, Tailscale and the Matter server use host networking. qBittorrent has no network of its own — it runs inside Gluetun's namespace (`network_mode: service:gluetun`), so its traffic leaves through the NordVPN WireGuard tunnel and its Traefik labels live on the `gluetun` service. Every other service uses the bridge networks above.

### Zigbee, Thread and Matter

An SMLIGHT SLZB-MR5U on the LAN (Ethernet) carries both radios; nothing is passed through over USB.
- **Zigbee:** Zigbee2MQTT reaches the coordinator at `ZIGBEE_ADAPTER_URL` (`tcp://<slzb-ip>:6638`, ember adapter) and publishes to Mosquitto. Mosquitto is on `internal` and published on `127.0.0.1:1883` only, which is how host-networked Home Assistant reaches it. Its password file is generated from `MQTT_USERNAME`/`MQTT_PASSWORD` on every container start; `config/mosquitto/mosquitto.conf` is mounted read-only straight from the repo
- **Zigbee2MQTT config:** `config/zigbee2mqtt/configuration.yaml` is a seed that `prepare-folders.sh` copies once. Zigbee2MQTT then owns the runtime file and writes the network key into it, so it is deliberately left out of `config-sync.sh`: a pull would commit the key. Adapter address and MQTT credentials come from `ZIGBEE2MQTT_CONFIG_*` env vars instead
- **Thread:** the OpenThread border router runs on the SLZB itself (mode "Thread + OTBR running on device", REST API on `:8080`); there is no OTBR container. It advertises the route to the Thread mesh by IPv6 router advertisement, so the host must accept RAs on `HOST_LAN_INTERFACE` and keep IPv6 forwarding off. `just verify` warns when the route is missing
- **Matter:** `matter-server` (matter.js) listens on `127.0.0.1:5580` only. `scripts/setup-matter-host.sh` (run by `install-host.sh`) opens UFW to `fd00::/8` and `fe80::/10` on the LAN interface, raises the UDP conntrack timeout to 3600 s for sleepy devices, and allows unprivileged ping

### Configuration

- `env.production.example` — production values for this specific hardware
- `.env` — actual secrets (gitignored, never committed)
- `config/traefik/traefik-users.example` — htpasswd-format credentials for Traefik dashboard

Key env variable groups:
- `HOST_*` — server identity and network (LAN IP: `192.168.10.10`)
- `*_ROOT` — filesystem mount points (`APPDATA_ROOT=/srv/homelab`, `MEDIA_ROOT=/srv/data`)
- `*_HOST` — service DNS names (`JELLYFIN_HOST=jellyfin.michalklos.com`, etc.)
- `MQTT_*`, `ZIGBEE_ADAPTER_URL` — broker credentials and the SLZB-MR5U's Zigbee radio (an IP, so Zigbee does not depend on AdGuard Home)
- `PUID`/`PGID` — UID/GID for linuxserver.io containers (default `1000`)
- `TZ=Europe/Warsaw`

### Hardware integration

`/dev/dri` is mounted into Jellyfin and Immich ML containers for Intel Quick Sync / VA-API hardware transcoding and OpenVINO inference.

### Backup

`scripts/backup.sh` dumps the Immich PostgreSQL database, then runs `restic backup` to `/mnt/backup-usb/restic`. Scheduled via cron: `0 3 * * 0` (Sunday 3 AM). Retention: 8 weekly + 6 monthly snapshots.

## Key docs

- `docs/INSTALL.md` — full step-by-step deployment
- `docs/JELLYFIN-TV.md` — LG G4 playback settings and measured codec compatibility

## Keeping docs in sync with the stack

Any architecture change must be reflected in the Markdown docs **in the same commit** — not left for later. This includes adding or removing a service, renaming a host, changing networks or ports, moving a config file, changing how remote access or DNS works, and adding or removing a `just` recipe.

Update whichever of these the change touches:
- `README.md` — the architecture diagram, the service tables (both the routed one and the no-web-UI one), the daily operations list, and the Stack summary
- `CLAUDE.md` — the service count, the networking model, the configuration section
- `docs/INSTALL.md` — setup steps and the `.env` variable table

Verify against reality rather than trusting the existing text, which has drifted before:
```bash
docker compose ps --format "{{.Service}}\t{{.Status}}"   # what actually runs
grep -nE "^  [a-z0-9_-]+:" docker-compose.yml            # what is defined
grep -nE "_HOST=" env.production.example                 # hostnames
```
Docs describing services that do not exist are worse than no docs: this repo once documented Vaultwarden behind a Cloudflare Tunnel and an Uptime Kuma instance, neither of which was ever in `docker-compose.yml`.
