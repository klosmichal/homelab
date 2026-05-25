#!/usr/bin/env bash
cat <<'TXT'
Restore quick notes:
1. Install a clean system and Docker.
2. Mount the backup disk.
3. Restore the repository and .env.
4. restic restore latest --target /
5. Start Compose.
6. If needed, restore the PostgreSQL dump for Immich:
   cat immich-postgres.sql | docker exec -i immich_postgres psql -U immich -d immich
TXT
