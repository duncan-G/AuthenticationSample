#!/usr/bin/env bash
# worker-manager.sh — Ensure worker is part of the Swarm
# - Runs every 5 minutes via systemd timer
# - If node is not in a swarm, attempts to join using tokens from DynamoDB lock
# - After successful join, notifies manager via API to set node labels (az, worker_type)

set -Eeuo pipefail
shopt -s inherit_errexit || true

log(){ printf '[ %s ] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
WORKER_ENV="/etc/worker-manager.env"
if [[ -f "$WORKER_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$WORKER_ENV"
fi

AWS_REGION="${AWS_REGION:-}"
CLUSTER_NAME="auth-sample-cluster"
SWARM_LOCK_TABLE="${SWARM_LOCK_TABLE:-}"
JOIN_TIMEOUT_SECONDS="${JOIN_TIMEOUT_SECONDS:-300}"

# ---------------------------------------------------------------------------
# IMDS helpers
# ---------------------------------------------------------------------------
imds_token(){ curl -s -X PUT --connect-timeout 1 --max-time 2 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true; }
imds_get(){ local p=$1 t; t=$(imds_token); [[ -n "$t" ]] || return 0; curl -s --connect-timeout 1 --max-time 3 -H "X-aws-ec2-metadata-token: $t" "http://169.254.169.254${p}" || true; }

if [[ -z "$AWS_REGION" ]]; then
  log "AWS region unknown; aborting"
  exit 0
fi

# ---------------------------------------------------------------------------
# Docker helpers
# ---------------------------------------------------------------------------
docker_state(){ docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive"; }
already_in_swarm(){ local s; s=$(docker_state); [[ "$s" == "active" || "$s" == "pending" ]]; }

# ---------------------------------------------------------------------------
# DynamoDB lock helpers
# ---------------------------------------------------------------------------
get_lock_raw(){
  aws --region "$AWS_REGION" dynamodb get-item \
    --table-name "$SWARM_LOCK_TABLE" \
    --key '{"cluster_name":{"S":"'"$CLUSTER_NAME"'"}}' \
    --consistent-read 2>/dev/null || true
}

read_lock(){
  # echo 3 lines: ip, worker_token, manager_token
  local j=$1
  jq -r '
    [
      .Item.manager_private_ip.S // "",
      .Item.swarm_join_token_worker.S // "",
      .Item.swarm_join_token_manager.S // ""
    ] | @tsv
  ' <<<"$j" 2>/dev/null || echo -e "\n\n\n"
}

join_swarm() {
  log "Joining swarm"
  # Tries to join within JOIN_TIMEOUT_SECONDS, refreshing from DynamoDB lock
  local deadline=$(( $(date +%s) + JOIN_TIMEOUT_SECONDS ))
  local target_ip="" token=""

  i=0;
  while (( $(date +%s) < deadline )); do
    local lj ip wt mt
    lj=$(get_lock_raw)
    read -r ip wt mt <<<"$(read_lock "$lj")"
    target_ip=${ip:-$target_ip}
    token=${wt:-$token}

    if [[ -n "$target_ip" && -n "$token" ]]; then
      log "Attempting docker swarm join to ${target_ip}:2377"
      if docker swarm join --token "$token" "${target_ip}:2377" >/dev/null 2>&1; then
        echo "$target_ip"
        return 0
      fi
    fi
    
    i=$((i + 10));
    log "Waiting for swarm join token to be available: $i seconds elapsed"
    sleep 10
  done
  return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main(){
  log "Worker manager starting"
  if already_in_swarm; then
    log "Worker already in swarm; nothing to do"
    return 0
  fi

  if join_swarm; then
    log "Joined swarm as worker"
    return 0
  else
    log "Join attempt timed out after ${JOIN_TIMEOUT_SECONDS}s; will retry next run"
    return 1
  fi
}

main "$@"
