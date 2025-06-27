#!/usr/bin/env bash
#
# docker-manager-setup.sh — Idempotent bootstrap script for promoting an
# Amazon Linux/EC2 instance to a Docker Swarm manager.
#
# Usage
#   sudo ./docker-manager-setup.sh            # run/continue setup
#   ./docker-manager-setup.sh --check-status  # query last‑run status programmatically
#
# Exit codes
#   0  success
#   1  unrecoverable failure (see log)
#   2  unknown / not started
#

set -Eeuo pipefail
shopt -s inherit_errexit   # Propagate ERR traps into subshells

############################################
# Globals
############################################
readonly LOG_FILE="/var/log/docker-manager-setup.log"
readonly STATUS_FILE="/tmp/docker-manager-setup.status"

readonly NETWORK_NAME="app-network"
readonly NETWORK_SUBNET="10.20.0.0/16"
readonly SSM_PREFIX="/docker/swarm"

############################################
# Helper utilities
############################################

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  echo "[ $(timestamp) ] $*" | tee -a "$LOG_FILE"
}

status() {
  local state="$1" msg="$2"
  echo "$state: $msg at $(timestamp)" >"$STATUS_FILE"
  log "STATUS ➜ $state – $msg"
}

check_status() {
  [[ -f "$STATUS_FILE" ]] || { echo "NOT_STARTED"; exit 3; }

  case $(cut -d':' -f1 <"$STATUS_FILE") in
    SUCCESS) echo "SUCCESS" ;;
    FAILED)  echo "FAILED"  ;;
    *)       echo "UNKNOWN" ;;
  esac
}

on_error() {
  local ec=$? line=$1
  status "FAILED" "line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR

############################################
# Early‑exit for status check
############################################

if [[ ${1:-} == "--check-status" ]]; then
  check_status
  exit $?
fi

############################################
# Ensure root privileges
############################################

if (( EUID != 0 )); then
  exec sudo -E "$0" "$@"
fi

############################################
# Main logic
############################################

log "Bootstrap initiated"
status "IN_PROGRESS" "Docker Swarm manager setup started"

get_aws_region() {
  local token region
  # Only IMDSv2
  token=$(curl -X PUT -s --connect-timeout 1 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  if [[ -n "$token" ]]; then
    region=$(curl -H "X-aws-ec2-metadata-token: $token" -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
    echo "$region"
  else
    log "ERROR: Could not obtain IMDSv2 token. Ensure the instance metadata service is enabled and IMDSv2 is supported."
    status "FAILED" "IMDSv2 token not available"
    exit 1
  fi
}

readonly AWS_REGION="${AWS_REGION:-$(get_aws_region)}"

if [[ -z "$AWS_REGION" ]]; then
  log "ERROR: AWS_REGION is not set and could not be determined from instance metadata."
  status "FAILED" "AWS_REGION not set"
  exit 1
fi

install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker already present – skipping installation"
    return
  fi

  log "Installing Docker engine…"
  yum -y -q update
  yum -y -q install docker
  systemctl enable --now docker
  usermod -aG docker ec2-user || true  # don't fail if user absent
  log "Docker installed and running ✅"
}

already_in_swarm() {
  local state
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "none")
  if [[ "$state" == "active" || "$state" == "pending" ]]; then
    return 0
  else
    return 1
  fi
}

init_swarm() {
  if already_in_swarm; then
    log "Swarm already initialised – skipping"
    return
  fi

  local token ip
  # Get IMDSv2 token first
  token=$(curl -X PUT -s --connect-timeout 5 --max-time 10 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  if [[ -n "$token" ]]; then
    ip=$(curl -H "X-aws-ec2-metadata-token: $token" -s --connect-timeout 5 --max-time 10 "http://169.254.169.254/latest/meta-data/local-ipv4" || true)
    log "DEBUG: Retrieved local IP: $ip"
  else
    log "ERROR: Could not obtain IMDSv2 token for metadata access"
    return 1
  fi
  
  if [[ -z "$ip" ]]; then
    log "ERROR: Could not retrieve local IP address from metadata"
    return 1
  fi
  
  docker swarm init --advertise-addr "$ip"
  log "Swarm initialised with advertise‑addr $ip"
  echo "$ip:2377"
}

store_ssm() {
  local name="$1" value="$2"
  aws --region "$AWS_REGION" ssm put-parameter \
     --name "$SSM_PREFIX/$name" \
     --value "$value" \
     --type String \
     --overwrite >/dev/null
}

create_overlay_network() {
  if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    log "Overlay network '$NETWORK_NAME' already exists – skipping"
    return
  fi
  docker network create --driver overlay --attachable \
                        --subnet "$NETWORK_SUBNET" \
                        "$NETWORK_NAME"
  log "Overlay network '$NETWORK_NAME' created"
}

main() {
  install_docker
  local manager_ip
  manager_ip=$(init_swarm)

  local worker_token
  worker_token=$(docker swarm join-token -q worker)

  log "Worker join command: docker swarm join --token $worker_token $manager_ip"

  log "Persisting configuration to SSM Parameter Store (prefix: $SSM_PREFIX)"
  store_ssm "worker-token" "$worker_token"
  store_ssm "manager-ip"   "$manager_ip"
  store_ssm "network-name" "$NETWORK_NAME"

  create_overlay_network

  log "Setup completed 🎉"
  status "SUCCESS" "Docker Swarm manager ready"
}

main "$@"
