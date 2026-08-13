#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
env_file=${ENV_FILE:-$repo_dir/.env.production}

fail() {
  echo "preflight: $1" >&2
  exit 1
}

[ -f "$env_file" ] || fail ".env.production is missing"
file_mode=$(stat -c %a "$env_file" 2>/dev/null || stat -f %Lp "$env_file")
[ "$file_mode" = "600" ] || fail ".env.production must use mode 600"

value() {
  sed -n "s/^$1=//p" "$env_file" | tail -n 1
}

for name in POSTGRES_PASSWORD DATABASE_URL CURSOR_SECRET MUTO_API_DOMAIN ACME_EMAIL \
  S3_ENDPOINT_URL S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY; do
  [ -n "$(value "$name")" ] || fail "$name is required"
done

[ "$(value STORAGE_ADAPTER)" = "s3" ] || fail "STORAGE_ADAPTER must be s3"
case "$(value S3_ENDPOINT_URL)" in
  https://*) ;;
  *) fail "S3_ENDPOINT_URL must use HTTPS" ;;
esac
[ "$(value AUTH_ADAPTER)" != "development" ] || {
  [ "$(value APP_ENV)" != "production" ] || \
    fail "development authentication cannot be production"
  [ -n "$(value DEVELOPMENT_AUTH_TOKEN)" ] || \
    fail "DEVELOPMENT_AUTH_TOKEN is required"
  [ -n "$(value DEVELOPMENT_ADMIN_AUTH_TOKEN)" ] || \
    fail "DEVELOPMENT_ADMIN_AUTH_TOKEN is required"
}
[ "$(value S3_BUCKET)" != "$(value BACKUP_S3_BUCKET)" ] || \
  fail "media and database backups must use separate buckets"
if [ "$(value APP_ENV)" = "production" ]; then
  for name in BACKUP_S3_ENDPOINT BACKUP_S3_BUCKET BACKUP_S3_ACCESS_KEY_ID \
    BACKUP_S3_SECRET_ACCESS_KEY BACKUP_AGE_RECIPIENT; do
    [ -n "$(value "$name")" ] || fail "$name is required in production"
  done
  case "$(value BACKUP_S3_ENDPOINT)" in
    https://*) ;;
    *) fail "BACKUP_S3_ENDPOINT must use HTTPS" ;;
  esac
fi

docker compose version >/dev/null
echo "production preflight passed"
