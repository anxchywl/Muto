#!/bin/sh
set -eu

backup_dir=${1:-${BACKUP_DIR:-/backups}}
max_age_hours=${BACKUP_MAX_AGE_HOURS:-26}
latest=$(find "$backup_dir" -type f -name 'muto-*.dump' -print | sort | tail -n 1)
[ -n "$latest" ] && [ -s "$latest" ] || {
  echo "no usable database backup found" >&2
  exit 1
}
sha256sum -c "$latest.sha256" >/dev/null
pg_restore --list "$latest" >/dev/null
age_seconds=$(( $(date +%s) - $(stat -c %Y "$latest") ))
[ "$age_seconds" -le $((max_age_hours * 3600)) ] || {
  echo "latest database backup is too old" >&2
  exit 1
}
echo "backup verified: $(basename "$latest")"
