#!/usr/bin/env bash
# BeforeInstall hook for CodeDeploy – runs before the new version is installed

set -euo pipefail

###########################
# Utility helpers
###########################
err() { printf "ERROR: %s\n" "$*" >&2; exit 1; }
log() { printf ">>> %s\n" "$*"; }

need_bin() { command -v "$1" >/dev/null 2>&1 || err "Required binary '$1' not found"; }

###########################
# Sanity checks
###########################
for bin in aws jq docker; do need_bin "$bin"; done

: "${DEPLOYMENT_GROUP_ID:?Missing DEPLOYMENT_GROUP_ID}"
: "${DEPLOYMENT_ID:?Missing DEPLOYMENT_ID}"

# shellcheck source=/dev/null
source "/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh"

: "${STACK_FILE:?Missing STACK_FILE}"
: "${SERVICE_NAME:?Missing SERVICE_NAME}"
: "${ENVIRONMENT:?Missing ENVIRONMENT}"

log "Starting BeforeInstall hook for ${SERVICE_NAME}..."
log "Deployment ID: ${DEPLOYMENT_ID}"
log "Service: ${SERVICE_NAME}"
log "Environment: ${ENVIRONMENT}"

###########################
# Retrieve network name from DynamoDB lock
###########################
LEADER_ENV="/etc/leader-manager.env"
if [[ -f "$LEADER_ENV" ]]; then
  # shellcheck source=/dev/null
  source "$LEADER_ENV"
fi

if [[ -z "$AWS_REGION" || -z "$SWARM_LOCK_TABLE" ]]; then
  log "Missing required env: AWS_REGION/SWARM_LOCK_TABLE"
  exit 1
fi

CLUSTER_NAME="auth-sample-cluster"

log "Retrieving overlay network name from DynamoDB..."
lock_json=$(aws --region "$AWS_REGION" dynamodb get-item \
  --table-name "$SWARM_LOCK_TABLE" \
  --key '{"cluster_name":{"S":"'"$CLUSTER_NAME"'"}}') || err "Could not read lock item from DynamoDB"

NETWORK_NAME=$(jq -r '.Item.swarm_overlay_network_name.S // empty' <<<"$lock_json") || true
[[ -n $NETWORK_NAME ]] || err "Network name not found in DynamoDB lock table"
log "✓ Retrieved network name from DynamoDB: $NETWORK_NAME"

###########################
# Verify overlay network
###########################
docker network inspect "$NETWORK_NAME" &>/dev/null \
  && log "✓ Overlay network '$NETWORK_NAME' exists" \
  || err "Required overlay network '$NETWORK_NAME' not found"

log "BeforeInstall hook completed successfully."
