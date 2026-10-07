#!/usr/bin/env bash
# Deploy one image tag on the production VM. Called by .github/workflows/backend-cd.yml:
#
#   sudo /opt/poonsuk/deploy.sh <image-tag>        # tag = full git SHA
#
# Order matters:
#   1. pull the new image          (fails early, nothing touched yet)
#   2. pg_dump                     (the only way back if a migration goes wrong)
#   3. migrations with the NEW image, while the OLD api is still serving
#   4. swap the api replicas ONE AT A TIME (api, then api-2); Nginx sends
#      traffic to whichever one is up, so there is no downtime
#   5. after each swap, wait for that replica's /health/ready
#      -> on failure, roll BOTH replicas back to the previous tag
#
# Rollback restores the previous IMAGE only. Migrations are not reverted, so
# every migration must stay compatible with the previous release
# (expand -> deploy -> contract in a later release). Restoring a dump is manual:
# see deploy/README.md "Rollback".
#
# During a rollout the old and new release serve requests side by side for a
# minute or two, so API changes must be backward compatible in the same way.
set -euo pipefail

TAG="${1:?usage: deploy.sh <image-tag>}"
APP_DIR=/opt/poonsuk
COMPOSE=(docker compose -f "$APP_DIR/docker-compose.prod.yml" --project-directory "$APP_DIR" -p poonsuk)
# Swapped in this order. Each one's host port is in the compose file.
API_SERVICES=(api api-2)
declare -A HEALTH_URL=(
  [api]=http://127.0.0.1:3000/health/ready
  [api-2]=http://127.0.0.1:3001/health/ready
)
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

wait_healthy() {
  for _ in $(seq 1 40); do
    curl -fsS --max-time 3 "$1" >/dev/null 2>&1 && return 0
    sleep 3
  done
  return 1
}

# Both replicas, so they never stay on different releases after a failure.
rollback_all() {
  if [[ -z "$PREV_TAG" ]]; then
    log "no previous tag to roll back to"
    return
  fi
  log "rolling back ${API_SERVICES[*]} to $PREV_TAG (schema NOT reverted; dump: $DUMP)"
  for s in "${API_SERVICES[@]}"; do
    IMAGE_TAG="$PREV_TAG" SENTRY_RELEASE="$PREV_TAG" "${COMPOSE[@]}" up -d --no-deps "$s"
  done
}

for svc in "${API_SERVICES[@]}"; do
  log "swap $svc"
  "${COMPOSE[@]}" up -d --no-deps "$svc"

  log "wait for ${HEALTH_URL[$svc]}"
  if ! wait_healthy "${HEALTH_URL[$svc]}"; then
    log "UNHEALTHY $svc — last logs:"
    "${COMPOSE[@]}" logs --tail=60 "$svc" || true
    rollback_all
    exit 1
  fi

  # Nginx marks a replica down for fail_timeout (10s) after failed attempts
  # during its swap. Wait that out so the other one is never taken down while
  # this one is still marked unavailable.
  sleep 10
done

echo "$TAG" > .deployed-tag
log "healthy — $TAG is live on ${API_SERVICES[*]}"

docker image prune -af --filter "until=168h" >/dev/null || true
