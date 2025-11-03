#!/usr/bin/env bash
# leader-manager.sh — Swarm leadership lease maintainer for AWS ASG nodes
# - Idempotent: safe to run from systemd timer.
# - Uses DynamoDB to elect exactly one node to run `docker swarm init`.
# - Others join the elected manager.

set -Eeuo pipefail
shopt -s inherit_errexit || true

log() {
  printf '[ %s ] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
LEADER_ENV="/etc/leader-manager.env"
if [[ -f "$LEADER_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$LEADER_ENV"
fi

AWS_REGION="${AWS_REGION:-}"
SWARM_LOCK_TABLE="${SWARM_LOCK_TABLE:-}"
JOIN_TIMEOUT_SECONDS="${JOIN_TIMEOUT_SECONDS:-300}"
LEASE_SECONDS="${LEASE_SECONDS:-300}"
SWARM_OVERLAY_NETWORK_NAME="${SWARM_OVERLAY_NETWORK_NAME:-app-network}"

# ---------------------------------------------------------------------------
# EC2 metadata (IMDSv2)
# ---------------------------------------------------------------------------
imds_token() {
  curl -s -X PUT --connect-timeout 2 \
    "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true
}
imds_get() {
  local p=$1 t
  t=$(imds_token)
  [[ -n "$t" ]] || return 0
  curl -s --connect-timeout 5 -H "X-aws-ec2-metadata-token: $t" \
    "http://169.254.169.254${p}" || true
}
my_instance_id=$(imds_get "/latest/meta-data/instance-id" || true)
my_private_ip=$(imds_get "/latest/meta-data/local-ipv4" || true)
if [[ -z "$my_instance_id" || -z "$my_private_ip" ]]; then
  log "ERROR: could not get instance-id or private IP from IMDS"
  exit 1
fi

# Cluster name is the EC2 instance ID
CLUSTER_NAME="auth-sample-cluster"

if [[ -z "$AWS_REGION" || -z "$SWARM_LOCK_TABLE" ]]; then
  log "Missing required env: AWS_REGION/SWARM_LOCK_TABLE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------
docker_state() { docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive"; }
is_leader()    { docker node inspect self --format '{{ .ManagerStatus.Leader }}' 2>/dev/null | grep -qi true; }

# Ensure the overlay network exists on the leader
create_overlay_network_if_missing() {
  local name="$SWARM_OVERLAY_NETWORK_NAME"
  [[ -n "$name" ]] || return 0

  if docker network inspect "$name" >/dev/null 2>&1; then
    log "Overlay network '$name' already exists"
    return 0
  fi

  log "Creating overlay network '$name'"
  if docker network create --driver overlay --attachable "$name" >/dev/null 2>&1; then
    log "Overlay network '$name' created"
  else
    log "WARNING: failed to create overlay network '$name'"
  fi
}

# ---------------------------------------------------------------------------
# DynamoDB helpers
# ---------------------------------------------------------------------------
get_lock_raw() {
  aws --region "$AWS_REGION" dynamodb get-item \
    --table-name "$SWARM_LOCK_TABLE" \
    --key '{"cluster_name":{"S":"'"$CLUSTER_NAME"'"}}' \
    --consistent-read 2>/dev/null || true
}

read_lock() {
  # echo 4 lines: lease, instance, ip, manager_token, worker_token
  local j=$1
  jq -r '
    [
      .Item.lease_expires_at.S // "",
      .Item.manager_instance_id.S // "",
      .Item.manager_private_ip.S // "",
      .Item.swarm_join_token_manager.S // "",
      .Item.swarm_join_token_worker.S // ""
    ] | @tsv
  ' <<<"$j" 2>/dev/null || echo -e "\n\n\n\n"
}

update_lock_with_condition() {
  # $1 prev_lease (may be "")
  # $2 "true" -> also publish tokens
  local prev_lease=$1
  local publish_tokens=${2:-false}

  local lease_until_iso
  lease_until_iso=$(date -u -d "+${LEASE_SECONDS} seconds" "+%Y-%m-%dT%H:%M:%SZ")

  local set_expr='SET manager_instance_id = :iid, manager_private_ip = :ip, lease_expires_at = :lease'
  local expr_vals='{":iid":{"S":"'"$my_instance_id"'"},":ip":{"S":"'"$my_private_ip"'"},":lease":{"S":"'"$lease_until_iso"'"}}'

  # Persist overlay network name if configured
  if [[ -n "$SWARM_OVERLAY_NETWORK_NAME" ]]; then
    set_expr+=' , swarm_overlay_network_name = :net'
    expr_vals=$(jq -c --arg net "$SWARM_OVERLAY_NETWORK_NAME" '. + {":net":{"S":$net}}' <<<"$expr_vals")
  fi

  if [[ "$publish_tokens" == "true" ]]; then
    local wt mt
    wt=$(docker swarm join-token -q worker 2>/dev/null || true)
    mt=$(docker swarm join-token -q manager 2>/dev/null || true)
    if [[ -n "$wt" && -n "$mt" ]]; then
      set_expr+=' , swarm_join_token_worker = :wt, swarm_join_token_manager = :mt'
      expr_vals=$(jq -c --arg wt "$wt" --arg mt "$mt" '. + {":wt":{"S":$wt},":mt":{"S":$mt}}' <<<"$expr_vals")
    fi
  fi

  local cond
  local expr_names
  if [[ -n "$prev_lease" ]]; then
    cond="attribute_not_exists(#cn) OR #lei = :prev"
    expr_names='{"#cn":"cluster_name","#lei":"lease_expires_at"}'
    expr_vals=$(jq -c --arg prev "$prev_lease" '. + {":prev":{"S":$prev}}' <<<"$expr_vals")
  else
    cond="attribute_not_exists(#cn)"
    expr_names='{"#cn":"cluster_name"}'
  fi

  aws --region "$AWS_REGION" dynamodb update-item \
    --table-name "$SWARM_LOCK_TABLE" \
    --key '{"cluster_name":{"S":"'"$CLUSTER_NAME"'"}}' \
    --update-expression "$set_expr" \
    --expression-attribute-names "$expr_names" \
    --expression-attribute-values "$expr_vals" \
    --condition-expression "$cond" \
    --return-values UPDATED_NEW >/dev/null
}

# ---------------------------------------------------------------------------
# Swarm actions
# ---------------------------------------------------------------------------
init_swarm_and_publish() {
  log "Initializing new swarm on $my_private_ip"
  if docker swarm init --advertise-addr "$my_private_ip" >/dev/null 2>&1; then
    # Ensure overlay network exists on fresh cluster
    create_overlay_network_if_missing || true
    # publish tokens, don't care if this exact write wins
    # Read current lease first (item may already exist from prior lock acquisition)
    local lj lease
    lj=$(get_lock_raw)
    read -r lease _ _ _ _ <<<"$(read_lock "$lj")"
    update_lock_with_condition "$lease" true || true
    log "Swarm initialized and tokens stored"
    return 0
  else
    log "Swarm init failed"
    return 1
  fi
}

join_swarm() {
  # $1 mode: "infinite" or "once" (default: once)
  local mode="${1:-once}"
  local target_ip=""
  local token=""
  local deadline=$(( $(date +%s) + JOIN_TIMEOUT_SECONDS ))

  while true; do
    # refresh from lock every loop; leader/tokens may change
    local lj lease inst ip mt wt
    lj=$(get_lock_raw)
    read -r lease inst ip mt wt <<<"$(read_lock "$lj")"
    target_ip=${ip:-$target_ip}
    token=${mt:-${wt:-$token}}

    if [[ -n "$target_ip" && -n "$token" ]]; then
      if docker swarm join --token "$token" "${target_ip}:2377" >/dev/null 2>&1; then
        log "Joined existing swarm"
        return 0
      fi
    fi

    if [[ "$mode" != "infinite" && $(date +%s) -ge $deadline ]]; then
      return 1
    fi

    sleep 10
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local state
  state=$(docker_state)

  local lj lease inst ip mt wt
  lj=$(get_lock_raw)
  read -r lease inst ip mt wt <<<"$(read_lock "$lj")"

  # A) Already the Swarm leader → just renew + publish tokens
  if is_leader; then
    log "This node is current Swarm leader; renewing lease"
    create_overlay_network_if_missing || true
    update_lock_with_condition "$lease" true || log "Lease renewal failed (race?)"
    return 0
  fi

  # B) Not in a swarm → try to claim lock and init; else join
  if [[ "$state" != "active" ]]; then
    log "Node not in a swarm; trying to claim lock for '$CLUSTER_NAME'"
    if update_lock_with_condition "$lease" false; then
      init_swarm_and_publish
      return 0
    fi

    log "Lock not claimable; trying to join existing swarm (infinite)"
    if join_swarm "infinite"; then
      return 0
    fi

    log "Failed to join existing swarm; trying to init new swarm"
    if update_lock_with_condition "$lease" false; then
      init_swarm_and_publish
      return 0
    fi

    log "Failed to init new swarm; joining existing swarm (once)"
    if join_swarm "once"; then
      return 0
    fi

    log "Failed to join existing swarm; giving up"
    return 1
  fi

  # D) We are in a swarm but not leader → nothing to do
  log "Node is in swarm but not leader; nothing to update"
}

main "$@"
