#!/usr/bin/env bash
# AfterInstall hook for CodeDeploy – runs after the new version is installed

set -euo pipefail

####################################
# Helper utilities
####################################
err()  { printf "ERROR: %s\n" "$*" >&2; exit 1; }
log() { printf ">>> %s\n"  "$*"; }
need_bin() { command -v "$1" &>/dev/null || err "Required binary '$1' not found"; }

####################################
# Sanity checks
####################################
need_bin docker

: "${DEPLOYMENT_GROUP_ID:?Missing DEPLOYMENT_GROUP_ID}"
: "${DEPLOYMENT_ID:?Missing DEPLOYMENT_ID}"

# shellcheck source=/dev/null
source "/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh"

log "Starting AfterInstall hook for ${SERVICE_NAME}..."

####################################
# Backup current stack configuration
####################################
if docker stack ls --format '{{.Name}}' | grep -qx "${SERVICE_NAME}"; then
  log "Creating backup of current stack '${SERVICE_NAME}'..."
  ts=$(date +%Y%m%d-%H%M%S)
  backup="/tmp/${SERVICE_NAME}-backup-${ts}.txt"

  docker stack ps "${SERVICE_NAME}" \
       --format 'table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.CurrentState}}' > "$backup"

  log "✓ Backup written to $backup"
else
  log "Stack '${SERVICE_NAME}' not found – nothing to back up"
fi

log "AfterInstall hook completed successfully."
