#!/usr/bin/env bash
#
# docker-worker-setup.sh — Idempotent bootstrap script for enrolling
# an Amazon Linux/EC2 instance as a **worker** node in an existing
# Docker Swarm.
#
# Usage
#   sudo ./docker-worker-setup.sh            # run/continue setup
#   ./docker-worker-setup.sh --check-status  # query last‑run status
#
# Exit codes
#   0  success
#   1  unrecoverable failure (see log)
#   2  unknown / not started
#

set -Eeuo pipefail
shopt -s inherit_errexit   # propagate ERR into functions/sub‑shells

############################################
# Globals
############################################
readonly LOG_FILE="/var/log/docker-worker-setup.log"
readonly STATUS_FILE="/tmp/docker-worker-setup.status"

readonly SSM_PREFIX="/docker/swarm"
readonly MAX_ATTEMPTS=30          # 30 × 10 s  ⇒  ~5 min

############################################
# Helper utilities
############################################

ts() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  echo "[ $(ts) ] $*" | tee -a "$LOG_FILE"
}

status() {
  local st="$1" msg="$2"
  echo "$st: $msg at $(ts)" >"$STATUS_FILE"
  log "STATUS ➜ $st – $msg"
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
# Early‑exit path for monitoring probes
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
# Functions
############################################
install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker already installed — skip"
    return
  fi

  log "Installing Docker engine…"
  yum -y -q update
  yum -y -q install docker
  systemctl enable --now docker
  usermod -aG docker ec2-user || true
  log "Docker installed ✅"
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

get_ssm_param() {
  local name="$1"
  aws --region "$AWS_REGION" ssm get-parameter --name "$SSM_PREFIX/$name" --query 'Parameter.Value' --output text 2>/dev/null || true
}

wait_for_manager() {
  log "Waiting for manager parameters in SSM… (max ${MAX_ATTEMPTS}×)"
  local attempt=1
  while (( attempt <= MAX_ATTEMPTS )); do
    local token ip
    token=$(get_ssm_param worker-token)
    ip=$(get_ssm_param manager-ip)
    if [[ -n $token && -n $ip ]]; then
      log "DEBUG: Found both parameters - token: ${token:0:10}... ip: $ip"
      echo "$token $ip"
      return 0
    fi
    log "Attempt $attempt/${MAX_ATTEMPTS} ➜ not ready yet; sleeping 10 s…"
    sleep 10
    (( attempt++ ))
  done
  log "Manager parameters not found after $MAX_ATTEMPTS attempts"
  return 1
}

join_swarm() {
  if already_in_swarm; then
    log "Node already part of a Swarm — skip join"
    return
  fi

  local token ip
  read -r token ip <<<"$(wait_for_manager)"
  [[ -n $token && -n $ip ]] || { log "Missing token or IP"; return 1; }

  log "Joining Swarm ($ip)…"
  docker swarm join --token "$token" "$ip"
  log "Swarm join complete 🎉"
}

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

############################################
# Main
############################################
log "Worker bootstrap initiated"
status "IN_PROGRESS" "Docker Swarm worker setup started"

install_docker
join_swarm

log "Setup complete. Node is operational as a Swarm worker."
status "SUCCESS" "Docker Swarm worker ready"
