#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
env_file=${ENV_FILE:-$repo_dir/.env.production}
deploy_ref=${DEPLOY_REF:-$(git -C "$repo_dir" rev-parse --verify HEAD)}
image="muto-backend:$deploy_ref"
compose="docker compose --env-file $env_file -f $repo_dir/docker-compose.production.yml"

# a host already running another project's caddy on 80/443 fronts muto
# through that proxy instead of starting muto's own
target=${DEPLOYMENT_TARGET:-}
if [ -z "$target" ]; then
  if docker ps --format '{{.Names}}' | grep -qx wished-caddy; then
    target=shared-host
  else
    target=dedicated
  fi
fi
if [ "$target" = "shared-host" ]; then
  compose="$compose -f $repo_dir/docker-compose.shared-host.yml"
else
  compose="$compose --profile dedicated"
fi

previous_image=$($compose ps -q backend | xargs -r docker inspect --format '{{.Config.Image}}')

DEPLOYMENT_TARGET=$target ENV_FILE=$env_file "$repo_dir/deploy/preflight.sh"
docker build --pull --tag "$image" --file "$repo_dir/backend/Dockerfile" "$repo_dir"

rollback() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$previous_image" ]; then
    echo "deployment failed; restoring previous backend image" >&2
    BACKEND_IMAGE=$previous_image $compose up -d --no-deps backend
  fi
  exit "$status"
}
trap rollback EXIT INT TERM

BACKEND_IMAGE=$image $compose up -d postgres
BACKEND_IMAGE=$image $compose run --rm --no-deps backup /usr/local/bin/backup.sh
BACKEND_IMAGE=$image $compose run --rm --no-deps backend \
  .venv/bin/alembic -c alembic.ini upgrade head
BACKEND_IMAGE=$image $compose up -d --remove-orphans

attempt=0
until curl --fail --silent --show-error --max-time 8 \
  "https://$(sed -n 's/^MUTO_API_DOMAIN=//p' "$env_file")/health/ready" >/dev/null; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 2
done
BACKEND_IMAGE=$image $compose exec -T backup /usr/local/bin/verify-backup.sh

trap - EXIT INT TERM
echo "deployment completed: $deploy_ref"
