# Homelab on MSI Cubi N ADL S-226BEU

This project is built around **Ubuntu Server LTS + Docker Compose + Traefik + Tailscale** as the simplest and most predictable stack for your requirements. Intel N200 with iGPU and `/dev/dri` is a good match for Jellyfin and optional Immich transcoding, and the MSI Cubi N ADL platform is suitable for a lightweight home server.[web:3][web:12]

The key architectural decision is: **run Home Assistant as Home Assistant Container, not Supervised**. Supervised is intended for a very specific host layout, and mixing it with your own custom Docker stack is widely considered a bad fit from a support and maintenance perspective.[web:18][web:26]

## Why this stack

- **OS:** Ubuntu Server 24.04 LTS — stable, simple, and convenient for Docker Compose.
- **Reverse proxy:** Traefik — automatic service discovery via labels, easier than hand-written Nginx configs for many services.
- **Service naming:** local DNS through `dnsmasq` on the host or local DNS records on the router; Traefik then serves names like `immich.home.arpa`.
- **Remote access:** Tailscale as the default and safest path for administrative services; optional **Cloudflare Tunnel only for Vaultwarden** if you want convenient access without VPN.
- **Docker management:** Portainer CE for management and Dozzle for logs; Dockge is also valid, but Portainer gives a broader operational view.
- **Monitoring:** Uptime Kuma + free notifications through `ntfy`, Telegram, or e-mail.[web:22][web:25]
- **Backups:** weekly `restic` backup to the second disk, plus database dumps.

## Requirement-by-requirement decisions

### 1. Operating system

**Recommendation: Ubuntu Server 24.04 LTS**, unless you want the leanest possible host, in which case Debian 12 is also an excellent choice. In practice the performance difference for your workload will be small, while Ubuntu gives a smoother onboarding path.

### 2. Docker and orchestration

**Docker Engine + Compose plugin** is enough. I do not recommend k3s or Swarm here, because they add complexity without meaningful benefit on a single machine.

### 3. Home Assistant

**Home Assistant Container** is the best compromise. You lose the add-on store and supervisor, but you gain full control, less hidden behavior, and no architectural conflict with the rest of your services.[web:18][web:26]

### 4. Bitwarden

If by “Bitwarden” you mean a self-hosted password vault on a small server, I strongly recommend **Vaultwarden**, because the official self-hosted Bitwarden stack is significantly heavier, while Vaultwarden remains compatible with Bitwarden clients and has much lower resource requirements.[web:7][web:10]

### 5. Reverse proxy

**Traefik > Nginx** for this case, because:
- services are exposed through Compose labels,
- middleware and routing are easier to maintain,
- you can keep a single public entry point on port 443 and use internal Docker networks for isolation.

Nginx is still a good choice if you want full manual control and already know its configuration model well; for a multi-service homelab, Traefik usually means less manual work.

### 6. Remote access

**Tailscale by default** for all administrative panels and private services. Tailscale provides a mesh VPN model and access policies, which makes it a strong fit for secure access to home services without exposing them publicly.[web:27]

**Exception: Vaultwarden.** If you want to use it very frequently from many devices without starting VPN each time, you can expose only `vault.example.com` through Cloudflare Tunnel. This works well in practice, but it means trusting an intermediary for your HTTPS path, so I would limit that exposure to this one service and protect it with MFA and strict access rules.[web:21][web:30]

### 7. Service names instead of IPs

The cleanest setup is:
- locally: `*.home.arpa` through `dnsmasq` on the host or local records on the router,
- remotely through Tailscale: MagicDNS, for example `immich.your-tailnet.ts.net`,
- publicly only if needed: for example `vault.yourdomain.tld` through Cloudflare Tunnel.

### 8. Start page

**Homarr** is the best fit. It is simple, polished, and works well as a dashboard for home services.

### 9. Docker management and logs

My preferred combination:
- **Portainer CE** for managing stacks, containers, volumes, and networks,
- **Dozzle** for fast log inspection,
- optional alternative to Portainer: **Dockge**, if your main goal is editing Compose files.

### 10. Backup

**Best practice:** do not rely on copying folders only; create application-consistent backups.

Plan:
- weekly `restic backup` to the second disk,
- PostgreSQL dump for Immich before backup,
- backup of configuration directories, bind-mounted volumes, and media directories defined in `env/.env`,
- retention through `restic forget --prune`.

### 11. Failure notifications

**Uptime Kuma + ntfy** is the easiest free combination. Uptime Kuma supports e-mail, Telegram, and ntfy notifications, and `ntfy` is trivial to run and has a mobile push app.[web:22][web:25]

### 12. Stirling PDF

Yes — it fits well as an additional container, preferably kept private behind Tailscale and Traefik.

## Architecture

```text
Internet / mobile device
        |
   [Tailscale]
        |
   +----+-------------------+
   |                        |
[Cloudflare Tunnel]   (optional, Vaultwarden only)
   |
[Traefik :443]
   |
   +-- homarr.home.arpa
   +-- immich.home.arpa
   +-- jellyfin.home.arpa
   +-- vault.home.arpa
   +-- ha.home.arpa
   +-- kuma.home.arpa
   +-- dozzle.home.arpa
   +-- portainer.home.arpa
   +-- pdf.home.arpa
```

## Resources and limits

Intel N200 and Intel UHD Graphics are suitable for a light homelab, but I would not treat this machine as a powerful box for many simultaneous 4K transcodes. Immich supports hardware transcoding, and Intel Quick Sync / VAAPI typically uses `/dev/dri` mapping.[web:12][web:6]

In practice that means:
- Jellyfin: yes, with hardware acceleration.
- Immich: yes, but ML and transcoding should be configured with moderation.
- Home Assistant, Samba, Vaultwarden, Homarr, Traefik, Kuma, Dozzle, Stirling: no issue.

## Repository

Project structure:

```text
homelab-msi-cubi/
├── README.md
├── env/
│   ├── .env.example
│   └── traefik-users.example
├── config/
│   ├── dnsmasq/
│   │   └── homelab.conf.example
│   └── netplan/
│       └── 01-cubi-static.yaml.example
├── compose/
│   ├── docker-compose.yml
│   └── cloudflared-compose.optional.yml
├── scripts/
│   ├── install-host.sh
│   ├── prepare-folders.sh
│   ├── backup.sh
│   ├── restore-notes.sh
│   └── healthcheck-smoke.sh
└── docs/
    ├── INSTALL.md
    ├── DECISIONS.md
    ├── DNS_AND_REMOTE_ACCESS.md
    ├── NAMING_CONVENTIONS.md
    ├── OPERATIONS.md
    └── PRODUCTION.md
```

## Quick start

1. Install Ubuntu Server 24.04 LTS.
2. Clone this repository and create `env/.env` from the example.
3. Attach the backup disk and mount it.
4. Run `scripts/install-host.sh`.
5. Run `scripts/prepare-folders.sh`.
6. Start the stack: `docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d`.
7. Configure Tailscale and optionally Cloudflare Tunnel for Vaultwarden only.

The full installation guide is available in `docs/INSTALL.md`.

## Additional network recommendation

If you have two TP-Link Archer BE230 routers running in mesh mode, you should create **two separate Wi‑Fi networks**: a private network and an IoT network. TP-Link Guest Network can isolate guest clients from the local network as long as you do not enable local network access for guests.[page:1][web:32]

**The mini PC should be placed in the private network.** The IoT segment should only contain less trusted devices that need internet access but should not have easy access to your server, computers, or data.[web:38]

## Production-ready update

The repository has been adapted to the following target setup: **1 M.2 disk for system and data + 1 USB disk for backups + 16 GB RAM + no public domain**. Locally you should use the `home.arpa` zone, which is intended for names inside a home network and does not require a public domain.[web:68]

Portainer and Dozzle serve different purposes: **Dozzle** is mainly for logs, while **Portainer** is for managing containers and stacks, so Portainer is optional rather than mandatory.[web:67][web:70]

Tailscale has a free Personal plan, so for home use you usually do not need a paid subscription; however, you do need a Tailscale client on the devices from which you want to access the homelab.[web:62][web:63]


## Final polish

The repository now includes a `justfile` for common operational commands, a sample `dnsmasq` configuration for the `home.arpa` zone, and service health checks in Docker Compose where lightweight checks are practical.[web:92][web:96][web:97]
