#!/bin/sh
set -eu
cd "$(dirname "$0")"
umask 077
mkdir -p backups
backup="backups/torly-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker compose exec -T db pg_dump -U torly -d torly -Fc > "$backup.partial"
mv "$backup.partial" "$backup"
echo "$backup"
