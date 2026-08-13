#!/bin/sh
set -eu

backup_dir=${BACKUP_DIR:-/backups}
retention_days=${BACKUP_RETENTION_DAYS:-14}
timestamp=$(date -u +%Y%m%d-%H%M%S)
temporary="$backup_dir/.muto-$timestamp.dump.tmp"
final="$backup_dir/muto-$timestamp.dump"

mkdir -p "$backup_dir"
pg_dump \
  --host "$POSTGRES_HOST" \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --format custom \
  --no-owner \
  --file "$temporary"
pg_restore --list "$temporary" >/dev/null
mv "$temporary" "$final"
sha256sum "$final" > "$final.sha256"

if [ -n "${BACKUP_S3_ENDPOINT:-}" ]; then
  : "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET is required}"
  : "${BACKUP_S3_ACCESS_KEY_ID:?BACKUP_S3_ACCESS_KEY_ID is required}"
  : "${BACKUP_S3_SECRET_ACCESS_KEY:?BACKUP_S3_SECRET_ACCESS_KEY is required}"
  : "${BACKUP_AGE_RECIPIENT:?BACKUP_AGE_RECIPIENT is required}"
  encrypted="$final.age"
  age --recipient "$BACKUP_AGE_RECIPIENT" --output "$encrypted" "$final"
  sha256sum "$encrypted" > "$encrypted.sha256"
  AWS_ACCESS_KEY_ID=$BACKUP_S3_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$BACKUP_S3_SECRET_ACCESS_KEY \
    aws --endpoint-url "$BACKUP_S3_ENDPOINT" s3 cp \
      "$encrypted" "s3://$BACKUP_S3_BUCKET/database/$(basename "$encrypted")" \
      --only-show-errors
  AWS_ACCESS_KEY_ID=$BACKUP_S3_ACCESS_KEY_ID \
  AWS_SECRET_ACCESS_KEY=$BACKUP_S3_SECRET_ACCESS_KEY \
    aws --endpoint-url "$BACKUP_S3_ENDPOINT" s3 cp \
      "$encrypted.sha256" \
      "s3://$BACKUP_S3_BUCKET/database/$(basename "$encrypted.sha256")" \
      --only-show-errors
  rm -f "$encrypted" "$encrypted.sha256"
fi

find "$backup_dir" -type f -name 'muto-*.dump*' -mtime "+$retention_days" -delete
echo "backup verified: $(basename "$final")"
