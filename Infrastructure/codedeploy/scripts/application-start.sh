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
: "${STACK_FILE:?Missing STACK_FILE}"
: "${SERVICE_NAME:?Missing SERVICE_NAME}"
: "${VERSION:?Missing VERSION}"

ARCHIVE_ROOT="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive"

# shellcheck source=/dev/null
source "${ARCHIVE_ROOT}/scripts/env.sh"

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

    log "Creating Docker config '${cfg_name}' from '${full_path}'"
    docker config inspect "$cfg_name" &>/dev/null && docker config rm "$cfg_name" || true
    docker config create "$cfg_name" "$full_path" \
      || err "Failed to create Docker config '${cfg_name}'"
  done
  shopt -u nullglob
else
  log "⚠︎ Config directory not found: $CONFIG_DIR (skipping config creation)"
fi

# Allow the Swarm to propagate new configs
sleep 5

####################################
# Deploy / update the stack
####################################
stack_src="${ARCHIVE_ROOT}/${STACK_FILE}"
[[ -f $stack_src ]] || err "Stack file not found: $stack_src"

tmp_stack="/tmp/${SERVICE_NAME}-stack.yml"
cp "$stack_src" "$tmp_stack"

log "Deploying stack '${SERVICE_NAME}'…"
docker stack deploy --compose-file "$tmp_stack" "$SERVICE_NAME"

####################################
# Basic health-check
####################################
sleep 10
docker stack ps "$SERVICE_NAME" --no-trunc

if ! docker stack ps "$SERVICE_NAME" --format '{{.CurrentState}}' | grep -Eq 'Running|Pending'; then
  err "Deployment failed to start properly"
fi

####################################
# Validate Service hot-swap
####################################
sleep 15
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
