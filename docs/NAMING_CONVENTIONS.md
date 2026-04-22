# Naming conventions

## Why this naming model

This repository now follows a more production-style naming scheme based on clear environment variable names, predictable hostnames, and stable directory roots. This aligns with common Docker Compose and environment-variable best practices, where configuration should be explicit and externalized from code.[web:77][web:83]

## Environment files

Recommended convention:
- `env/env.production.example` — committed example for production-like deployments,
- `env/.env.example` — convenience copy based on the same values,
- `env/.env` — your real local deployment file, created manually and not committed,
- optional future files such as `env/env.staging.example` if you ever add another environment.

This keeps configuration separated from the repository while still documenting all required variables.[web:77][web:83][web:84]

## Variable naming rules

The repository now uses:
- `HOST_*` for host networking values,
- `*_ROOT` for top-level directory roots,
- `*_HOST` for service FQDNs,
- explicit uppercase snake_case names for all runtime configuration.

Examples:
- `HOST_FQDN`
- `HOST_LAN_IP`
- `APPDATA_ROOT`
- `MEDIA_ROOT`
- `TRAEFIK_HOST`
- `JELLYFIN_PUBLISHED_SERVER_URL`

This makes the intent of each variable easier to understand and keeps the configuration easier to scale later.[web:83][web:89]

## Host naming rules

Use a short and stable host FQDN such as `cubi.home.arpa` for the machine itself, and separate service names for applications such as `immich.home.arpa` and `vault.home.arpa`. Using `home.arpa` is appropriate for private home-network naming and does not require a public domain.[web:68][web:82]

## Compose naming

The Compose project name is now controlled through `COMPOSE_PROJECT_NAME`, which is an officially supported way to make container naming predictable across environments.[web:81]
