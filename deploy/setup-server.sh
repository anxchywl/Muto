#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "run setup-server.sh as root" >&2
  exit 1
}

deploy_user=${DEPLOY_USER:-deploy}
app_dir=${APP_DIR:-/home/$deploy_user/muto}
id "$deploy_user" >/dev/null 2>&1 || {
  echo "deploy user does not exist" >&2
  exit 1
}

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl docker.io docker-compose-v2 git
systemctl enable --now docker
usermod -aG docker "$deploy_user"
install -d -m 0750 -o "$deploy_user" -g "$deploy_user" "$app_dir" "$app_dir/repo"

echo "server runtime installed"
echo "allow inbound 22, 80 and 443 in the provider firewall"
echo "clone the repository into $app_dir/repo as $deploy_user"
echo "create $app_dir/repo/.env.production with mode 600"
