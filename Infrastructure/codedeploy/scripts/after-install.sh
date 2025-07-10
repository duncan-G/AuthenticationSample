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
: "${STACK_NAME:?Missing STACK_NAME}"

# shellcheck source=/dev/null
source "/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh"

log "Starting AfterInstall hook for ${SERVICE_NAME:-unknown}..."

####################################
# Backup current stack configuration
####################################
if docker stack ls --format '{{.Name}}' | grep -qx "${STACK_NAME}"; then
  log "Creating backup of current stack '${STACK_NAME}'..."
  ts=$(date +%Y%m%d-%H%M%S)
  backup="/tmp/${STACK_NAME}-backup-${ts}.txt"

  docker stack ps "${STACK_NAME}" \
       --format 'table {{.Name}}\t{{.Image}}\t{{.Node}}\t{{.CurrentState}}' > "$backup"

  log "✓ Backup written to $backup"
else
  log "Stack '${STACK_NAME}' not found – nothing to back up"
fi

log "AfterInstall hook completed successfully."
