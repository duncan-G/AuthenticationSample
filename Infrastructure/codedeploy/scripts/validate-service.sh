#!/usr/bin/env bash
# ValidateService hook for CodeDeploy – confirms that every replica reports a healthy Docker HEALTHCHECK

set -euo pipefail

####################################
# Helper utilities
####################################
err()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }
log()  { printf ">>> %s\n"  "$*"; }
need_bin() { command -v "$1" &>/dev/null || err "Required binary '$1' not found"; }

####################################
# Sanity checks & setup
####################################
for b in docker; do need_bin "$b"; done

: "${DEPLOYMENT_GROUP_ID:?Missing DEPLOYMENT_GROUP_ID}"
: "${DEPLOYMENT_ID:?Missing DEPLOYMENT_ID}"

ARCHIVE_ROOT="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive"
# shellcheck source=/dev/null
source "${ARCHIVE_ROOT}/scripts/env.sh"

: "${SERVICE_NAME:?Missing SERVICE_NAME}"

log "Starting ValidateService hook for ${SERVICE_NAME}…"

####################################
# 1. Wait until the correct number of replicas are Running
####################################
log "Waiting for tasks to reach the Running state…"

MAX_TASK_ATTEMPTS=30
for ((i=1; i<=MAX_TASK_ATTEMPTS; i++)); do
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
# 2. Wait for every container's HEALTHCHECK to report 'healthy'
####################################
log "Waiting for all containers to report a healthy status…"

MAX_HEALTH_ATTEMPTS=30
for ((i=1; i<=MAX_HEALTH_ATTEMPTS; i++)); do
  # Refresh container list each pass in case tasks re-schedule
  mapfile -t containers < <(docker ps -q --filter "label=com.docker.swarm.service.name=${SERVICE_NAME}")

  unhealthy=0
  for cid in "${containers[@]}"; do
    # If the image has no HEALTHCHECK, .State.Health is null – treat that as healthy
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid")
    [[ "$health" != "healthy" && "$health" != "none" ]] && unhealthy=$((unhealthy+1))
  done

  log "Attempt ${i}/${MAX_HEALTH_ATTEMPTS}: $(( ${#containers[@]} - unhealthy ))/${#containers[@]} containers healthy"

  if (( unhealthy == 0 )); then
    log "✓ All containers are healthy"
    break
  fi

  (( i == MAX_HEALTH_ATTEMPTS )) && err "Containers did not become healthy within expected time"
  sleep 5
done

log "✓ Correct image is running and all health checks have passed"
log "ValidateService hook completed successfully."
