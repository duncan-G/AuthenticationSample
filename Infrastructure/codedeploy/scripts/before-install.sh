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
# Retrieve secrets
###########################
if [[ "${REQUIRE_TLS:-false}" == "true" ]]; then
  : "${SECRET_NAME:?Missing SECRET_NAME}"

  log "Retrieving secrets from AWS Secrets Manager..."
  SECRET_JSON=$(aws secretsmanager get-secret-value \
                   --secret-id "$SECRET_NAME" \
                   --query 'SecretString' --output text) || err "Could not retrieve secret '$SECRET_NAME'"

  APP_NAME=$(jq -r '.Infrastructure_APP_NAME // empty' <<<"$SECRET_JSON")
  CERTIFICATE_STORE=$(jq -r '.Infrastructure_CERTIFICATE_STORE // empty' <<<"$SECRET_JSON")

  [[ -n $APP_NAME && -n $CERTIFICATE_STORE ]] \
    || err "Missing 'APP_NAME' or 'CERTIFICATE_STORE' in secret '$SECRET_NAME'"

  log "✓ Retrieved APP_NAME and CERTIFICATE_STORE"

  ###########################
  # Determine latest run ID
  ###########################
  log "Fetching latest certificate run ID from S3..."
  LATEST_RUN_ID=$(aws s3 cp "s3://${CERTIFICATE_STORE}/${APP_NAME}/last-renewal-run-id" - 2>/dev/null | tr -d '\n') \
    || err "Could not retrieve latest run ID (s3://${CERTIFICATE_STORE}/${APP_NAME}/last-renewal-run-id)"
  [[ -n $LATEST_RUN_ID ]] || err "last-renewal-run-id is empty"
  log "✓ Latest certificate run ID: $LATEST_RUN_ID"

  ###########################
  # Validate Docker Swarm & secrets
  ###########################
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "none")
  [[ "$state" == "active" ]] \
    || err "Docker Swarm is not active"

  CERT_PREFIX=${CERT_PREFIX:-}
  declare -a secrets=(
    "${CERT_PREFIX}-cert.pem-${LATEST_RUN_ID}"
    "${CERT_PREFIX}-privkey.pem-${LATEST_RUN_ID}"
    "${CERT_PREFIX}-cert.pfx-${LATEST_RUN_ID}"
  )

  for s in "${secrets[@]}"; do
    docker secret inspect "$s" &>/dev/null \
      && log "✓ Docker secret '$s' exists" \
      || err "Docker secret '$s' not found"
  done
fi

###########################
# Retrieve network name from SSM
###########################
log "Retrieving overlay network name from SSM..."
NETWORK_NAME=$(aws ssm get-parameter \
                  --name "/docker/swarm/network-name" \
                  --query 'Parameter.Value' \
                  --output text) || err "Could not retrieve network name from SSM"

[[ -n $NETWORK_NAME ]] || err "Network name from SSM is empty"
log "✓ Retrieved network name: $NETWORK_NAME"

###########################
# Verify overlay network
###########################
docker network inspect "$NETWORK_NAME" &>/dev/null \
  && log "✓ Overlay network '$NETWORK_NAME' exists" \
  || err "Required overlay network '$NETWORK_NAME' not found"

log "BeforeInstall hook completed successfully."
