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
  printf '[ %s ] %s\n' "$(ts)" "$*" | tee -a "$LOG_FILE" >&2
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

## Docker should come pre-installed. Keep this function if
## we switch to minimal AMI.
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

install_ecr_credential_helper() {
  if command -v docker-credential-ecr-login &>/dev/null; then
    log "ECR credential helper already present — skip"
    return
  fi

  log "Installing ECR credential helper…"
  # Try dnf first (newer systems), fall back to yum
  if command -v dnf &>/dev/null; then
    dnf install -y amazon-ecr-credential-helper
  else
    yum -y -q install amazon-ecr-credential-helper
  fi
  log "ECR credential helper installed ✅"
}

configure_docker_ecr_auth() {
  log "Configuring Docker to use ECR credential helper…"
  
  # Create Docker config directory if it doesn't exist
  mkdir -p /root/.docker
  
  # Write Docker config.json to use ECR credential helper (root)
  echo '{
  "credsStore": "ecr-login"
}' > /root/.docker/config.json

  # Also configure for ec2-user if it exists
  if id ec2-user &>/dev/null; then
    mkdir -p ~ec2-user/.docker
    echo '{
  "credsStore": "ecr-login"
}' > ~ec2-user/.docker/config.json
    chown -R ec2-user:ec2-user ~ec2-user/.docker
  fi
  
  # Configure system-wide Docker config for ECR authentication
  mkdir -p /etc/docker
  echo '{
  "credsStore": "ecr-login"
}' > /etc/docker/config.json
  
  log "Docker ECR authentication configured ✅"
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
  local attempt=1 token ip

  while (( attempt <= MAX_ATTEMPTS )); do
    token=$(get_ssm_param worker-token)
    ip=$(get_ssm_param manager-ip)

    # Only check that both parameters exist and are not placeholder values
    if [[ -n $token && -n $ip && $token != "placeholder" && $ip != "placeholder" ]]; then
      log "DEBUG: Found parameters – token: ${token:0:10}… ip: $ip"
      printf '%s %s\n' "$token" "$ip"   # <── ONLY stdout from the function
      return 0
    else
      if [[ $token == "placeholder" || $ip == "placeholder" ]]; then
        log "Attempt $attempt/$MAX_ATTEMPTS ➜ found placeholder values, waiting for manager to update SSM parameters…"
      else
        log "Attempt $attempt/$MAX_ATTEMPTS ➜ parameters not found (token: ${token:-empty}, ip: ${ip:-empty}); sleeping 10 s…"
      fi
    fi

    sleep 10
    (( attempt++ ))
  done

  log "Manager parameters not ready after $MAX_ATTEMPTS attempts"
  return 1
}

join_swarm() {
  if already_in_swarm; then
    log "Node already part of a Swarm — skipping join"
    return 0
  fi

  local token ip
  if read -r token ip < <(wait_for_manager); then   # process-substitution, not word-split
    log "Joining Swarm ($ip)…"
    if docker swarm join --token "$token" "$ip"; then
      log "Swarm join complete 🎉"
    else
      log "ERROR: Failed to join swarm with token and IP"
      return 1
    fi
  else
    log "ERROR: Failed to obtain valid manager parameters from SSM"
    log "This usually means the manager setup hasn't completed yet or failed"
    return 1
  fi
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
install_ecr_credential_helper
configure_docker_ecr_auth
join_swarm

log "Setup complete. Node is operational as a Swarm worker."
status "SUCCESS" "Docker Swarm worker ready"
