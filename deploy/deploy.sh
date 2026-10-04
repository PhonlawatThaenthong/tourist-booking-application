#!/usr/bin/env bash
# Deploy one image tag on the production VM. Called by .github/workflows/backend-cd.yml:
#
#   sudo /opt/poonsuk/deploy.sh <image-tag>        # tag = full git SHA
#
# Order matters:
#   1. pull the new image          (fails early, nothing touched yet)
#   2. pg_dump                     (the only way back if a migration goes wrong)
#   3. migrations with the NEW image, while the OLD api is still serving
#   4. swap the api container
#   5. wait for /health/ready      -> on failure, roll the api back to the previous tag
#
# Rollback restores the previous IMAGE only. Migrations are not reverted, so
# every migration must stay compatible with the previous release
# (expand -> deploy -> contract in a later release). Restoring a dump is manual:
# see deploy/README.md "Rollback".
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
APP_DIR=/opt/poonsuk
COMPOSE=(docker compose -f "$APP_DIR/docker-compose.prod.yml" --project-directory "$APP_DIR" -p poonsuk)
HEALTH_URL=http://127.0.0.1:3000/health/ready
KEEP_BACKUPS=14

cd "$APP_DIR"
[[ -f .env ]] || { echo "missing $APP_DIR/.env" >&2; exit 1; }

# One deploy at a time (GitHub concurrency also guards this, belt and braces)
exec 9>/var/lock/poonsuk-deploy.lock
flock -n 9 || { echo "another deploy is running" >&2; exit 1; }

# Read single keys with grep: .env holds values with spaces/<> (SMTP_FROM,
# PAYMENT_NOTE) that would break `source .env`.
env_get() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2- || true; }

PREV_TAG="$(cat .deployed-tag 2>/dev/null || true)"
log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }

export IMAGE_TAG="$TAG"
export SENTRY_RELEASE="$TAG"

log "tag $TAG (previous: ${PREV_TAG:-none})"

log "pull"
"${COMPOSE[@]}" pull api

log "postgres + redis up"
"${COMPOSE[@]}" up -d --wait postgres redis

log "backup"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP="backups/pre-${TAG:0:12}-${TS}.dump"
"${COMPOSE[@]}" exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$DUMP"
log "  $DUMP ($(du -h "$DUMP" | cut -f1))"
BUCKET="$(env_get BACKUP_BUCKET)"
if [[ -n "$BUCKET" ]]; then
  gcloud storage cp --quiet "$DUMP" "gs://${BUCKET}/db/" && log "  copied to gs://${BUCKET}/db/"
fi
ls -1t backups/*.dump 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f

log "migrations (new image, old api still serving)"
"${COMPOSE[@]}" run --rm --no-deps api npm run --silent migration:run:prod

log "swap api"
"${COMPOSE[@]}" up -d --no-deps api

log "wait for $HEALTH_URL"
healthy=false
for _ in $(seq 1 40); do
  if curl -fsS --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then healthy=true; break; fi
  sleep 3
done

if ! $healthy; then
  log "UNHEALTHY — last api logs:"
  "${COMPOSE[@]}" logs --tail=60 api || true
  if [[ -n "$PREV_TAG" ]]; then
    log "rolling back api to $PREV_TAG (schema NOT reverted; dump: $DUMP)"
    IMAGE_TAG="$PREV_TAG" SENTRY_RELEASE="$PREV_TAG" "${COMPOSE[@]}" up -d --no-deps api
  fi
  exit 1
fi

echo "$TAG" > .deployed-tag
log "healthy — $TAG is live"

docker image prune -af --filter "until=168h" >/dev/null || true
