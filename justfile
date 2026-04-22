set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
  @just --list

# Copy the production example environment file
init-env:
  cp -n env/env.production.example env/.env

# Start the core stack only
up:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Start the core stack with Dozzle
up-dozzle:
  docker compose --profile dozzle --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Start the core stack with Portainer
up-portainer:
  docker compose --profile portainer --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Start the core stack with Dozzle and Portainer
up-full:
  docker compose --profile dozzle --profile portainer --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Stop the stack
stop:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml down

# Pull updated images and recreate containers
update:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml pull
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml up -d

# Show current container status
ps:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml ps

# Follow logs for all services
logs:
  docker compose --env-file ./env/.env -f ./compose/docker-compose.yml logs -f --tail=200

# Run the backup script
backup:
  bash ./scripts/backup.sh

# Run the smoke test script
check:
  bash ./scripts/healthcheck-smoke.sh
