#!/usr/bin/env bash
#
# docker-manager-setup.sh — Idempotent bootstrap script for promoting an
# Amazon Linux/EC2 instance to a Docker Swarm **manager**.
#
# Usage
#   sudo ./docker-manager-setup.sh            # run/continue setup
#   ./docker-manager-setup.sh --check-status  # query last-run status programmatically
#
# Exit codes (for --check-status)
#   0  SUCCESS
#   1  FAILED
#   2  UNKNOWN
#   3  NOT_STARTED
#
# Any other invocation returns standard shell exit codes (0 = ok, 1 = error).

set -Eeuo pipefail
shopt -s inherit_errexit   # Bash ≥4.4 required; propagates ERR traps into subshells

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
  # Write to both logfile and console (console on stderr so $(..) captures stay clean)
  printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2
}

status() {
  local state="$1" msg="$2"
  printf '%s: %s at %s\n' "$state" "$msg" "$(timestamp)" >"$STATUS_FILE"
  log "STATUS ➜ $state – $msg"
}

check_status() {
  [[ -f "$STATUS_FILE" ]] || { echo "NOT_STARTED"; exit 3; }

  case $(cut -d':' -f1 <"$STATUS_FILE") in
    SUCCESS) echo SUCCESS;  exit 0 ;;
    FAILED)  echo FAILED;   exit 1 ;;
    UNKNOWN) echo UNKNOWN;  exit 2 ;;
    *)       echo UNKNOWN;  exit 2 ;;
  esac
}

on_error() {
  local ec=$? line=$1
  status "FAILED" "line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR

############################################
# Early-exit for status check
############################################

if [[ ${1:-} == "--check-status" ]]; then
  check_status  # exits internally with correct code
fi

############################################
# Ensure root privileges
############################################

if (( EUID != 0 )); then
  exec sudo -E "$0" "$@"
fi

############################################
# Dependency checks / installation (jq, awscli, docker)
############################################


install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker already present – skipping installation"
    return
  fi

  log "Installing Docker engine …"
  yum -y -q update
  yum -y -q install docker
  systemctl enable --now docker
  usermod -aG docker ec2-user || true  # don't fail if user absent
  log "Docker installed and running ✅"
}

install_ecr_credential_helper() {
  if command -v docker-credential-ecr-login &>/dev/null; then
    log "ECR credential helper already present – skipping installation"
    return
  fi

  log "Installing ECR credential helper …"
  # Try dnf first (newer systems), fall back to yum
  if command -v dnf &>/dev/null; then
    dnf install -y amazon-ecr-credential-helper
  else
    yum -y -q install amazon-ecr-credential-helper
  fi
  log "ECR credential helper installed ✅"
}

configure_docker_ecr_auth() {
  log "Configuring Docker to use ECR credential helper …"
  
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
  
  # Create ECR cache directory for the ec2-user with correct permissions
  # This allows the ECR credential helper to work with ProtectHome=read-only
  if id ec2-user &>/dev/null; then
    mkdir -p /home/ec2-user/.ecr
    chown ec2-user:ec2-user /home/ec2-user/.ecr
    chmod 0700 /home/ec2-user/.ecr
  fi
   log "Docker ECR authentication configured ✅"
}

############################################
# AWS helpers
############################################

get_aws_region() {
  local token region
  # IMDSv2
  token=$(curl -X PUT -s --connect-timeout 2 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  if [[ -n "$token" ]]; then
    region=$(curl -H "X-aws-ec2-metadata-token: $token" -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
    echo "$region"
  else
    log "ERROR: Could not obtain IMDSv2 token. Ensure Instance Metadata Service v2 is enabled."
    status "FAILED" "IMDSv2 token not available"
    exit 1
  fi
}

############################################
# Swarm helpers
############################################

already_in_swarm() {
  local state
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  [[ "$state" == "active" || "$state" == "pending" ]]
}

init_swarm() {
  # Returns manager listen addr (ip:2377) via stdout

  if already_in_swarm; then
    local addr
    addr=$(docker info --format '{{.Swarm.NodeAddr}}:2377' 2>/dev/null || true)
    log "Swarm already initialised – manager at $addr"
    [[ -n "$addr" ]] && printf '%s\n' "$addr"
    return 0
  fi

  # Discover this instance's primary IP via IMDSv2
  local token ip
  token=$(curl -X PUT -s --connect-timeout 5 --max-time 10 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true)
  if [[ -z "$token" ]]; then
    log "ERROR: Could not obtain IMDSv2 token for metadata access"
    return 1
  fi
  ip=$(curl -H "X-aws-ec2-metadata-token: $token" -s --connect-timeout 5 --max-time 10 "http://169.254.169.254/latest/meta-data/local-ipv4" || true)
  [[ -n "$ip" ]] || { log "ERROR: Could not retrieve local IP address"; return 1; }
  log "DEBUG: Retrieved local IP: $ip"

  if docker swarm init --advertise-addr "$ip" >/dev/null 2>&1; then
    log "Swarm initialised with advertise-addr $ip"
    printf '%s\n' "$ip:2377"
  else
    log "ERROR: docker swarm init failed"
    return 1
  fi
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

############################################
# Main logic
############################################

main() {
  log "Bootstrap initiated"
  status "IN_PROGRESS" "Docker Swarm manager setup started"

  install_docker
  install_ecr_credential_helper
  configure_docker_ecr_auth

  # Determine AWS region (env-override allowed)
  readonly AWS_REGION="${AWS_REGION:-$(get_aws_region)}"
  [[ -n "$AWS_REGION" ]] || { log "AWS region unknown"; status "FAILED" "No AWS region"; exit 1; }
  log "Using AWS region: $AWS_REGION"

  # Initialise or query Swarm
  local manager_ip
  if ! manager_ip=$(init_swarm); then
    status "FAILED" "Swarm initialisation failed"
    exit 1
  fi
  [[ -n "$manager_ip" ]] || { log "ERROR: Manager IP empty"; status "FAILED" "Manager IP empty"; exit 1; }

  # Obtain worker join token
  local worker_token
  worker_token=$(docker swarm join-token -q worker)

  log "Worker join command: docker swarm join --token $worker_token $manager_ip"

  # Persist to SSM Parameter Store
  log "Persisting configuration to SSM Parameter Store (prefix: $SSM_PREFIX)"
  store_ssm "worker-token" "$worker_token"
  store_ssm "manager-ip"   "$manager_ip"
  store_ssm "network-name" "$NETWORK_NAME"

  create_overlay_network

  log "Setup completed 🎉"
  status "SUCCESS" "Docker Swarm manager ready"
}

main "$@"