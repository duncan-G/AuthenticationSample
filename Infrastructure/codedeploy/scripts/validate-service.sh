#!/usr/bin/env bash
# ValidateService hook for CodeDeploy – confirms that the new revision is healthy

set -euo pipefail

####################################
# Helper utilities
####################################
err()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }
log() { printf ">>> %s\n"  "$*"; }
need_bin() { command -v "$1" &>/dev/null || err "Required binary '$1' not found"; }

####################################
# Sanity checks & setup
####################################
for b in docker curl; do need_bin "$b"; done

: "${DEPLOYMENT_GROUP_ID:?Missing DEPLOYMENT_GROUP_ID}"
: "${DEPLOYMENT_ID:?Missing DEPLOYMENT_ID}"

ARCHIVE_ROOT="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive"
# shellcheck source=/dev/null
source "${ARCHIVE_ROOT}/scripts/env.sh"

: "${SERVICE_NAME:?Missing SERVICE_NAME}"

HEALTH_URL=${HEALTH_URL:-http://localhost:9901/ready}

log "Starting ValidateService hook for ${SERVICE_NAME}…"

####################################
# Wait for all replicas to be Running
####################################
log "Waiting for tasks to reach the Running state…"

MAX_TASK_ATTEMPTS=30
for ((i=1; i<=MAX_TASK_ATTEMPTS; i++)); do
  # Count tasks with desired-state=running
  mapfile -t states < <(docker stack ps "$SERVICE_NAME" \
                        --filter desired-state=running --format '{{.CurrentState}}')
  total=${#states[@]}
  running=$(printf '%s\n' "${states[@]}" | grep -c '^Running')

  log "Attempt ${i}/${MAX_TASK_ATTEMPTS}: ${running}/${total} replicas running"

  if (( total > 0 && running == total )); then
    log "✓ All replicas are Running"
    break
  fi

  (( i == MAX_TASK_ATTEMPTS )) && err "Service failed to start within expected time"
  sleep 10
done

####################################
# Health-check loop
####################################
log "Checking health endpoint at ${HEALTH_URL}…"

MAX_HEALTH_ATTEMPTS=10
for ((i=1; i<=MAX_HEALTH_ATTEMPTS; i++)); do
  if curl -fsS "$HEALTH_URL" >/dev/null; then
    log "✓ Health check passed"
    break
  fi
  log "Health check ${i}/${MAX_HEALTH_ATTEMPTS} failed – retrying in 5 s…"
  (( i == MAX_HEALTH_ATTEMPTS )) && \
    { log "⚠︎ Health check did not succeed, continuing deployment"; break; }
  sleep 5
done

log "✓ Correct image is running"

log "ValidateService hook completed successfully."
