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
: "${ENVIRONMENT:?Missing ENVIRONMENT}"

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
# Substitute network name & cert timestamp
###########################
get_cert_timestamp() {
  local cert_dir="/var/lib/certificate-manager/certs"

  # Get numeric subdirectories, sort by DESC (newest first)
  local -a ts_dirs found_ts
  mapfile -t ts_dirs < <(
    find "$cert_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | grep -E '^[0-9]+$' \
    | sort -nr
  )

  # Loop through in DESC order, check folder contents for *_<ts> files
  for ts in "${ts_dirs[@]}"; do
    local ts_path="${cert_dir}/${ts}"

    # List regular files in the timestamp directory
    mapfile -t files < <(find "$ts_path" -mindepth 1 -maxdepth 1 -type f -printf '%f\n')

    # Must have at least one file, and every file must end with _<ts>
    if ((${#files[@]} == 0)); then
      continue
    fi

    local all_match=true
    for f in "${files[@]}"; do
      local secret_name="${f}_${ts}"
      if ! docker secret inspect "$secret_name" &>/dev/null; then
        all_match=false
        break
      fi
    done

    if $all_match; then
      echo "$ts"
      return
    fi
  done

  err "No valid certificate timestamp found in $cert_dir (no *_<ts> file sets found)."
}

get_network_name_from_dynamodb() {
  local leader_env="/etc/leader-manager.env"
  if [[ -f "$leader_env" ]]; then
    # shellcheck source=/dev/null
    source "$leader_env"
  fi

  : "${AWS_REGION:?Missing AWS_REGION (expected in $leader_env)}"
  : "${SWARM_LOCK_TABLE:?Missing SWARM_LOCK_TABLE (expected in $leader_env)}"
  local cluster_name="auth-sample-cluster"

  lock_json=$(aws --region "$AWS_REGION" dynamodb get-item \
    --table-name "$SWARM_LOCK_TABLE" \
    --key '{"cluster_name":{"S":"'"$cluster_name"'"}}') || err "Could not read lock item from DynamoDB"

  local network_name=$(jq -r '.Item.swarm_overlay_network_name.S // empty' <<<"$lock_json") || true
  [[ -n $network_name ]] || err "Network name not found in DynamoDB lock table"
  echo "$network_name"
}

CERT_TIMESTAMP=$(get_cert_timestamp)
NETWORK_NAME=$(get_network_name_from_dynamodb)

stack_src="${ARCHIVE_ROOT}/${STACK_FILE}"

sed -i \
  -e "s|\${NETWORK_NAME}|${NETWORK_NAME}|g" \
  -e "s|\${TS}|${CERT_TIMESTAMP}|g" \
  -e "s|\${ENVIRONMENT}|${ENVIRONMENT}|g" \
  -e "s|\${VERSION}|${VERSION}|g" \
  -e "s|\${SERVICE_NAME}|${SERVICE_NAME}|g" \
  "$stack_src"

###########################
# Verify overlay network
###########################
docker network inspect "$NETWORK_NAME" &>/dev/null \
  && log "✓ Overlay network '$NETWORK_NAME' exists" \
  || err "Required overlay network '$NETWORK_NAME' not found"

####################################
# Deploy / update the stack
####################################
[[ -f $stack_src ]] || err "Stack file not found: $stack_src"

tmp_stack="/tmp/${STACK_FILE}"
cp "$stack_src" "$tmp_stack"

log "Deploying stack '${SERVICE_NAME}'"
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
