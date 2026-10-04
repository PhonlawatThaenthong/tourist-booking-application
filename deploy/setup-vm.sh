#!/usr/bin/env bash
# One-time bootstrap of the production VM (Ubuntu 24.04 LTS on GCE).
#
#   sudo bash setup-vm.sh <domain> <letsencrypt-email> <gar-region>
#   e.g. sudo bash setup-vm.sh api.example.com you@psu.ac.th asia-southeast1
#
# Idempotent: safe to re-run. Needs this repo's deploy/nginx/poonsuk-api.conf
# next to it (copy the whole deploy/ folder to the VM first).
# After this script: create /opt/poonsuk/.env (see deploy/README.md), then
# let the GitHub Actions CD workflow do the first deploy.
set -euo pipefail

DOMAIN="${1:?usage: setup-vm.sh <domain> <email> <gar-region>}"
EMAIL="${2:?usage: setup-vm.sh <domain> <email> <gar-region>}"
GAR_REGION="${3:?usage: setup-vm.sh <domain> <email> <gar-region>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/poonsuk

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

echo "==> packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y docker.io docker-compose-v2 nginx certbot curl
command -v gcloud >/dev/null || snap install google-cloud-cli --classic
systemctl enable --now docker nginx

echo "==> swap (2 GB) — e2-small has 2 GB RAM for api + postgres + redis"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Artifact Registry auth for root (uses the VM's service account)"
gcloud auth configure-docker "${GAR_REGION}-docker.pkg.dev" --quiet

echo "==> app dir"
mkdir -p "$APP_DIR/backups"
chmod 750 "$APP_DIR"

echo "==> nginx: HTTP-only site so certbot can answer the ACME challenge"
mkdir -p /var/www/certbot
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/poonsuk-bootstrap <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location ^~ /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 503; }
}
NGINX

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  ln -sf /etc/nginx/sites-available/poonsuk-bootstrap /etc/nginx/sites-enabled/poonsuk-bootstrap
  nginx -t && systemctl reload nginx
  echo "==> certificate for ${DOMAIN} (DNS A record must already point here)"
  certbot certonly --webroot -w /var/www/certbot -d "$DOMAIN" \
    --email "$EMAIL" --agree-tos --no-eff-email --non-interactive
fi

echo "==> nginx: real site"
sed "s/__DOMAIN__/${DOMAIN}/g" "$HERE/nginx/poonsuk-api.conf" > /etc/nginx/sites-available/poonsuk-api
ln -sf /etc/nginx/sites-available/poonsuk-api /etc/nginx/sites-enabled/poonsuk-api
rm -f /etc/nginx/sites-enabled/poonsuk-bootstrap
nginx -t && systemctl reload nginx

echo "==> reload nginx after every renewal (certbot.timer renews twice a day)"
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/sh
systemctl reload nginx
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
certbot renew --dry-run

echo
echo "Done. Next:"
echo "  1. sudo nano ${APP_DIR}/.env   (template: deploy/README.md, step 7)"
echo "  2. sudo chmod 600 ${APP_DIR}/.env"
echo "  3. trigger the 'Backend CD' workflow on GitHub"
echo "  (API returns 502 until the first deploy — that is expected)"
