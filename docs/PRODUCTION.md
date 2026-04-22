# Production-ready version

## Hardware assumptions

This version of the repository is prepared for:
- **1 M.2 disk** for system and service data,
- **1 USB disk** dedicated to backups,
- **16 GB RAM**,
- no public domain.

This is a reasonable setup for the planned homelab as long as media storage does not grow too aggressively and you do not expect many simultaneous heavy transcodes.[web:12][web:3]

## Can you use service names without a public domain

Yes. You do not need a public domain to use service names in the local network. That is exactly what the **`home.arpa`** local-use domain is for: it is reserved for internal home network naming and is meant to be resolved by your local DNS.[web:68]

That is why this repository uses names such as:
- `home.home.arpa`
- `immich.home.arpa`
- `jellyfin.home.arpa`
- `vault.home.arpa`
- `ha.home.arpa`

## Storage layout

With one M.2 disk and 16 GB RAM, the recommended layout is:
- system + Docker + active application data on the M.2 disk,
- backups only on the USB disk,
- no active application data on the USB disk, because that is usually slower and less reliable if the drive is disconnected.

Suggested directories:
- `/srv/homelab` — service configuration and state,
- `/srv/data` — media and user data,
- `/mnt/backup-usb` — mount point for the backup disk,
- `/mnt/backup-usb/restic` — backup repository.

## What 16 GB RAM means here

16 GB RAM is enough for this stack, but it is still wise to stay conservative with Immich ML, Jellyfin, and Home Assistant running at the same time. The heaviest parts are usually Immich machine learning, the Immich database, and video transcoding.[web:12]

If you notice memory pressure, the first thing to reduce is usually Immich ML activity or scheduling heavier jobs outside your main Jellyfin usage windows.

## Portainer vs Dozzle

**Dozzle does not replace Portainer**, because they solve different problems. Dozzle is mainly for real-time Docker log viewing, while Portainer is a management panel for containers, stacks, volumes, and networks.[web:67][web:70]

The practical answer is:
- if you only want fast access to logs — **Dozzle is enough**,
- if you want to restart stacks, inspect volumes, edit deployments, and manage Docker through a GUI — **Portainer is useful**.[web:67][web:70]

In this repository, both tools are left as **optional Compose profiles**. You can run only Dozzle, only Portainer, or both.

### How to use the profiles

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

## Tailscale — do you need a subscription

No, for home use you usually do not need a paid subscription. Tailscale has a free Personal plan which, according to the documentation, supports up to 6 users in one tailnet.[web:62][web:63]

## Tailscale — do you need another app

Yes, but only on the devices from which you want to connect. Tailscale works through a client installed on the devices that should join your private mesh network, such as your phone, laptop, or tablet.[web:75][web:63]

In practice that means:
- the mini PC runs Tailscale as a container or system client,
- your phone has the Tailscale app installed,
- your laptop has the Tailscale app installed,
- all of them sign in to the same Tailscale account and become part of the same tailnet.[web:75][web:63]

This is the tradeoff that lets you avoid exposing all of your services directly to the public internet.

## Recommended choice for your setup

For your current setup, I recommend:
- **local DNS + `home.arpa`**,
- **Tailscale Free** for remote access,
- **Dozzle enabled**,
- **Portainer optional**, if you want a GUI for operational management,
- no public domain at the beginning,
- no public exposure of services except maybe a future Vaultwarden exception.[web:68][web:63]


## Deployment values pre-filled for your environment

This repository is now pre-filled for your current target layout:
- private LAN: `192.168.10.0/24`
- router / gateway: `192.168.10.1`
- mini PC: `192.168.10.10`
- host FQDN: `cubi.home.arpa`
- local DNS zone: `home.arpa`
- backup mount point: `/mnt/backup-usb`

You still need to replace secrets such as passwords and tokens, but the network-related placeholders are already aligned to your intended deployment.[web:106][web:97]
