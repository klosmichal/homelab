# Operations guide

## Why this file exists

The goal of this file is to make day-2 operations consistent and easy to repeat. Instead of remembering long Docker Compose commands, you can use the included `justfile` as a thin task runner layer, which is a common pattern for operational convenience in small infrastructure repositories.[web:96][web:99]

## Recommended operational commands

Initialize the local environment file:
```bash
just init-env
```

Start the core stack:
```bash
just up
```

Start the core stack with Dozzle:
```bash
just up-dozzle
```

Start the full stack with Dozzle and Portainer:
```bash
just up-full
```

Update all images and recreate containers:
```bash
just update
```

Run the backup manually:
```bash
just backup
```

Run the smoke checks:
```bash
just check
```

## Health checks

The Compose file now includes health checks for the services where lightweight in-container checks are practical. This follows common Docker Compose guidance: health checks should be defined in Compose, kept simple, and used to distinguish a merely running container from a truly ready service.[web:92][web:80][web:98]

Immich dependencies now use health-based startup ordering for PostgreSQL and Redis, so the application waits for those dependencies to become healthy before starting.[web:92][web:95]

## Notes on health checks

Health checks should not be overly aggressive, because each run creates overhead inside the container. Moderate intervals such as 30 seconds are a practical compromise for small homelab environments.[web:104][web:101]
