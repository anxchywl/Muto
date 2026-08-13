#!/bin/sh
set -eu

dump=${1:?usage: deploy/restore.sh path-to-dump}
repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
compose="docker compose --env-file $repo_dir/.env.production -f $repo_dir/docker-compose.production.yml"

[ -f "$dump" ] && [ -s "$dump" ] || {
  echo "backup does not exist or is empty" >&2
  exit 1
}
$compose run --rm --no-deps backup pg_restore --list < "$dump" >/dev/null
printf "type restore to replace the Muto database: "
read -r confirmation
[ "$confirmation" = "restore" ] || exit 1

$compose run --rm --no-deps backup /usr/local/bin/backup.sh
$compose stop backend maintenance
$compose exec -T postgres sh -c \
  "dropdb --username=\"\$POSTGRES_USER\" --if-exists \"\$POSTGRES_DB\" && createdb --username=\"\$POSTGRES_USER\" \"\$POSTGRES_DB\""
$compose exec -T postgres sh -c \
  "pg_restore --username=\"\$POSTGRES_USER\" --dbname=\"\$POSTGRES_DB\" --no-owner --exit-on-error --single-transaction" \
  < "$dump"
$compose run --rm --no-deps backend .venv/bin/alembic -c alembic.ini upgrade head
$compose up -d backend maintenance
echo "restore completed"
