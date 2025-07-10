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
: "${STACK_NAME:?Missing STACK_NAME}"
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
log "Creating new versioned Envoy Docker configs…"

declare -a CONFIG_FILES=(
  "configs/envoy-release.yaml"
  "configs/envoy.cds.yaml"
  "configs/envoy.rds.yaml"
  "configs/envoy.sds.yaml"
)

map_config_name() {
  case "$1" in
    envoy-release) echo "envoy_config"   ;;
    envoy.cds)     echo "envoy_clusters" ;;
    envoy.rds)     echo "envoy_routes"   ;;
    envoy.sds)     echo "envoy_secrets"  ;;
    *)             echo "${1//./_}"      ;;
  esac
}

for rel_path in "${CONFIG_FILES[@]}"; do
  full_path="${ARCHIVE_ROOT}/${rel_path}"
  [[ -f $full_path ]] || { log "⚠︎ Config file not found: ${rel_path}"; continue; }

  base=$(basename "${rel_path%.*}")      # strip .yaml|.yml
  cfg_name="$(map_config_name "$base")_${VERSION}"

  log "Creating Docker config '${cfg_name}'"
  docker config inspect "$cfg_name" &>/dev/null && docker config rm "$cfg_name" || true
  docker config create "$cfg_name" "$full_path" \
    || err "Failed to create Docker config '${cfg_name}'"
done

# Allow the Swarm to propagate new configs
sleep 5

####################################
# Deploy / update the stack
####################################
stack_src="${ARCHIVE_ROOT}/${STACK_FILE}"
[[ -f $stack_src ]] || err "Stack file not found: $stack_src"

tmp_stack="/tmp/${STACK_NAME}-stack.yml"
cp "$stack_src" "$tmp_stack"

log "Deploying stack '${STACK_NAME}'…"
docker stack deploy --compose-file "$tmp_stack" "$STACK_NAME"

####################################
# Basic health-check
####################################
sleep 10
docker stack ps "$STACK_NAME" --no-trunc

if ! docker stack ps "$STACK_NAME" --format '{{.CurrentState}}' | grep -Eq 'Running|Pending'; then
  err "Deployment failed to start properly"
fi

####################################
# Validate Envoy hot-swap
####################################
sleep 15
ENVOY_SERVICE_ID=$(docker service ls --filter "label=service=${SERVICE_NAME}" \
                                  --format '{{.ID}}' | head -n1)

if [[ -n $ENVOY_SERVICE_ID ]]; then
  state=$(docker service ps "$ENVOY_SERVICE_ID" --format '{{.CurrentState}}' | head -n1)
  log "Envoy service state: $state"
  [[ $state == Running* ]] \
    && log "✓ Envoy hot-swap successful" \
    || log "⚠︎ Envoy service still starting"
else
  log "⚠︎ Envoy service not found for validation"
fi

####################################
# Prune old Docker configs (keep latest 3)
####################################
log "Cleaning up old Envoy config versions…"
for cfg in envoy_config envoy_clusters envoy_routes envoy_secrets; do
  mapfile -t old < <(docker config ls --format '{{.Name}}' \
             | grep "^${cfg}_" | sort -r | tail -n +4)
  for o in "${old[@]}"; do
    log "Removing outdated config: $o"
    docker config rm "$o" || true
  done
done

log "ApplicationStart hook completed successfully."
