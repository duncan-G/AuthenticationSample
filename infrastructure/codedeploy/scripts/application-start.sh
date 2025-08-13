#!/usr/bin/env bash
# ApplicationStart hook for CodeDeploy – starts the new revision and triggers an Envoy hot-swap

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
for b in docker aws jq; do need_bin "$b"; done

: "${DEPLOYMENT_GROUP_ID:?Missing DEPLOYMENT_GROUP_ID}"
: "${DEPLOYMENT_ID:?Missing DEPLOYMENT_ID}"

ARCHIVE_ROOT="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive"

# shellcheck source=/dev/null
source "${ARCHIVE_ROOT}/scripts/env.sh"

: "${STACK_FILE:?Missing STACK_FILE}"
: "${SERVICE_NAME:?Missing SERVICE_NAME}"
: "${VERSION:?Missing VERSION}"

log "Starting ApplicationStart hook for ${SERVICE_NAME}..."

####################################
# Create versioned Envoy configs
####################################
log "Creating new versioned configs…"

# Determine config directory packaged with the revision
CONFIG_DIR="${ARCHIVE_ROOT}/configs"

if [[ -d $CONFIG_DIR ]]; then
  # Iterate over all YAML/YML files inside the config directory
  shopt -s nullglob
  for full_path in "$CONFIG_DIR"/*.yml "$CONFIG_DIR"/*.yaml; do
    [[ -f $full_path ]] || continue

    base=$(basename "${full_path%.*}")        # Strip extension
    base_clean=${base//./_}                     # Replace dots with underscores
    cfg_name="${base_clean}_config_${VERSION}"

    if docker config inspect "$cfg_name" &>/dev/null; then
      log "Docker config '${cfg_name}' already exists for this version, reusing..."
    else
      log "Creating Docker config '${cfg_name}' from '${full_path}'"
      docker config create "$cfg_name" "$full_path" \
        || err "Failed to create Docker config '${cfg_name}'"
    fi
  done
  shopt -u nullglob
else
  log "⚠︎ Config directory not found: $CONFIG_DIR (skipping config creation)"
fi

# Allow the Swarm to propagate new configs
sleep 5

###########################
# Substitute network name
###########################
log "Retrieving overlay network name from SSM..."
NETWORK_NAME=$(aws ssm get-parameter \
                  --name "/docker/swarm/network-name" \
                  --query 'Parameter.Value' \
                  --output text) || err "Could not retrieve network name from SSM"

[[ -n $NETWORK_NAME ]] || err "Network name from SSM is empty"
log "✓ Retrieved network name: $NETWORK_NAME"

sed -i \
  -e "s|\${NETWORK_NAME}|${NETWORK_NAME}|g" \
  "${ARCHIVE_ROOT}/${STACK_FILE}"

###########################
# Verify overlay network
###########################
docker network inspect "$NETWORK_NAME" &>/dev/null \
  && log "✓ Overlay network '$NETWORK_NAME' exists" \
  || err "Required overlay network '$NETWORK_NAME' not found"

####################################
# Deploy / update the stack
####################################
stack_src="${ARCHIVE_ROOT}/${STACK_FILE}"
[[ -f $stack_src ]] || err "Stack file not found: $stack_src"

tmp_stack="/tmp/${SERVICE_NAME}-stack.yml"
cp "$stack_src" "$tmp_stack"

log "Deploying stack '${SERVICE_NAME}'…"
docker stack deploy --with-registry-auth --compose-file "$tmp_stack" "$SERVICE_NAME"

####################################
# Basic health-check
####################################

# Wait for service to move past Starting state
log "Waiting for service to start..."
sleep 10
  
retries=0
max_retries=30
while docker stack ps "$SERVICE_NAME" --format '{{.CurrentState}}' | grep -q '^Starting'; do
  retries=$((retries + 1))
  if [ "$retries" -gt "$max_retries" ]; then
    err "Service failed to move past Starting state after $max_retries attempts"
  fi
  log "Service still starting, waiting... (attempt $retries/$max_retries)"
  sleep 5
done


if ! docker stack ps "$SERVICE_NAME" --format '{{.CurrentState}}' | grep -Eq 'Running|Pending'; then
  err "Deployment failed to start properly"
fi

log "Service is running"

####################################
# Validate Service hot-swap
####################################
SERVICE_ID=$(docker service ls --filter "label=service=${SERVICE_NAME}" \
                                  --format '{{.ID}}' | head -n1)

if [[ -n $SERVICE_ID ]]; then
  state=$(docker service ps "$SERVICE_ID" --format '{{.CurrentState}}' | head -n1)
  log "Service state: $state"
  [[ $state == Running* ]] \
    && log "✓ Service hot-swap successful" \
    || log "⚠︎ Service still starting"
else
  log "⚠︎ Service not found for validation"
fi

####################################
# Prune old Docker configs (keep latest 3)
####################################
log "Cleaning up old config versions…"

if [[ -d $CONFIG_DIR ]]; then
  shopt -s nullglob
  for full_path in "$CONFIG_DIR"/*.yml "$CONFIG_DIR"/*.yaml; do
    [[ -f $full_path ]] || continue
    base=$(basename "${full_path%.*}")
    base_clean=${base//./_}
    prefix="${base_clean}_config_"

    mapfile -t old < <(docker config ls --format '{{.Name}}' \
               | grep "^${prefix}" | sort -r | tail -n +4)
    for o in "${old[@]}"; do
      log "Removing outdated config: $o"
      docker config rm "$o" || true
    done
  done
  shopt -u nullglob
fi

log "ApplicationStart hook completed successfully."
