#!/usr/bin/env bash
# shellcheck shell=bash

# ----------------------------------------------------------------------------
# worker.sh — EC2 user data bootstrap for Docker Swarm worker
#
# Purpose
# - Provision an Amazon Linux EC2 instance as a Docker Swarm worker node.
#
# What this script does
# - Installs Docker, jq, awscli, and the Amazon ECR credential helper; configures
#   Docker to use the credential store for root and (optionally) `SETUP_USER`.
# - Installs and configures the CloudWatch agent to ship this script's log file.
# - Reads manager-provided values from AWS Systems Manager Parameter Store under
#   `SSM_PREFIX` (set by the manager script): `worker-token`, `manager-ip`.
# - Waits/retries until the manager parameters are available, then joins the
#   swarm as a worker and labels the node with its AZ for placement constraints.
#
# Inputs/overrides via environment variables
# - `AWS_REGION` (auto-detected if unset), `LOG_FILE`, `SSM_PREFIX`, `PROJECT_NAME`,
#   `SETUP_USER`, `MAX_ATTEMPTS`, `SLEEP_SECONDS`.
#
# Usage
# - Invoked as EC2 user data by Terraform for instances tagged `Role=worker`,
#   and/or executed via SSM associations. Designed to be idempotent and safe to
#   re-run.
# ----------------------------------------------------------------------------

set -Eeuo pipefail
shopt -s inherit_errexit || true

# ----------------------------------------------
# Globals (override with env vars if needed)
# ----------------------------------------------
readonly LOG_FILE="${LOG_FILE:-/var/log/docker-worker-setup.log}"
readonly SSM_PREFIX="${SSM_PREFIX:-/docker/swarm}"
readonly PROJECT_NAME="${PROJECT_NAME:-docker-worker}"
readonly SETUP_USER="${SETUP_USER:-ec2-user}"
readonly MAX_ATTEMPTS=${MAX_ATTEMPTS:-60}
readonly SLEEP_SECONDS=${SLEEP_SECONDS:-5}

# ----------------------------------------------
# Logging & error handling
# ----------------------------------------------
timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2; }
on_error(){ local ec=$? line=${1:-?}; log "ERROR: line $line exited with code $ec"; exit "$ec"; }
trap 'on_error $LINENO' ERR

# ----------------------------------------------
# Package manager helpers
# ----------------------------------------------
pm_cmd(){ if command -v dnf >/dev/null 2>&1; then echo dnf; elif command -v yum >/dev/null 2>&1; then echo yum; else return 1; fi; }
pm(){ local pm; pm=$(pm_cmd); case "$1" in update) sudo "$pm" -y -q update || true;; install) shift; sudo "$pm" -y -q install "$@";; esac; }

# ----------------------------------------------
# IMDS (EC2 metadata) helpers
# ----------------------------------------------
imds_token(){ curl -X PUT -s --connect-timeout 2 "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true; }
imds_get(){ local path=$1 token; token=$(imds_token); [[ -n "$token" ]] || { log "ERROR: IMDSv2 token unavailable"; return 1; }; curl -s --connect-timeout 5 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254${path}" || true; }
get_aws_region(){ imds_get "/latest/dynamic/instance-identity/document" | jq -r '.region' 2>/dev/null || true; }
get_az(){        imds_get "/latest/meta-data/placement/availability-zone"; }

# ----------------------------------------------
# Docker & ECR creds
# ----------------------------------------------
install_docker_stack(){
  pm update
  pm install docker jq awscli || true
  systemctl enable --now docker
  if id "$SETUP_USER" >/dev/null 2>&1; then usermod -aG docker "$SETUP_USER" || true; fi

  # ECR credential helper
  if ! command -v docker-credential-ecr-login >/dev/null 2>&1; then pm install amazon-ecr-credential-helper || true; fi

  # Configure Docker creds for root and (optional) SETUP_USER
  mkdir -p /root/.docker /etc/docker
  cat >/root/.docker/config.json <<'JSON'
{"credsStore":"ecr-login"}
JSON
  if id "$SETUP_USER" >/dev/null 2>&1; then
    mkdir -p ~"$SETUP_USER"/.docker
    cat >~"$SETUP_USER"/.docker/config.json <<'JSON'
{"credsStore":"ecr-login"}
JSON
    chown -R "$SETUP_USER:$SETUP_USER" ~"$SETUP_USER"/.docker
  fi
  cat >/etc/docker/config.json <<'JSON'
{"credsStore":"ecr-login"}
JSON
}

wait_for_docker(){
  local attempts=0
  until docker info >/dev/null 2>&1; do sleep 2; attempts=$((attempts+1)); [[ $attempts -le 30 ]] || { log "Docker not ready after ${attempts} attempts"; return 1; }; done
}

# ----------------------------------------------
# CloudWatch agent
# ----------------------------------------------
install_cloudwatch_agent(){
  if ! command -v amazon-cloudwatch-agent >/dev/null 2>&1; then pm install amazon-cloudwatch-agent || true; fi
  mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
  cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$LOG_FILE",
            "log_group_name": "/aws/ec2/${PROJECT_NAME}-docker-worker",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          }
        ]
      }
    }
  }
}
EOF
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true
}

# ----------------------------------------------
# Swarm helpers
# ----------------------------------------------
already_in_swarm(){ local state; state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive"); [[ "$state" == "active" || "$state" == "pending" ]]; }

get_ssm_param(){ local name=$1; aws --region "$AWS_REGION" ssm get-parameter --name "$SSM_PREFIX/$name" --query 'Parameter.Value' --output text 2>/dev/null || true; }

wait_for_manager(){
  log "Waiting for manager SSM params at prefix $SSM_PREFIX (max ${MAX_ATTEMPTS} attempts)"
  local attempt=1 token ip
  while (( attempt <= MAX_ATTEMPTS )); do
    token=$(get_ssm_param worker-token)
    ip=$(get_ssm_param manager-ip)
    if [[ -n $token && -n $ip && $token != "placeholder" && $ip != "placeholder" && $token != "None" && $ip != "None" ]]; then
      printf '%s %s\n' "$token" "$ip"
      return 0
    fi
    log "Attempt $attempt/$MAX_ATTEMPTS — manager params not ready; sleeping $SLEEP_SECONDS s…"
    sleep "$SLEEP_SECONDS"
    (( attempt++ ))
  done
  return 1
}

join_swarm(){
  if already_in_swarm; then log "Node already part of a swarm — skipping join"; return 0; fi
  local token ip
  if read -r token ip < <(wait_for_manager); then
    log "Joining swarm at $ip"
    docker swarm join --token "$token" "$ip"
  else
    log "ERROR: Manager parameters not available from SSM after $MAX_ATTEMPTS attempts"
    return 1
  fi
}

label_node_with_az(){
  local az node_id
  az=$(get_az || true)
  node_id=$(docker info -f '{{.Swarm.NodeID}}' || true)
  if [[ -n "$az" && -n "$node_id" ]]; then docker node update --label-add "az=${az}" "$node_id" || true; fi
}

# ----------------------------------------------
# Main
# ----------------------------------------------
log "Bootstrap initiated — Docker Swarm worker setup starting"

install_docker_stack
install_cloudwatch_agent

readonly AWS_REGION="${AWS_REGION:-$(get_aws_region)}"
[[ -n "${AWS_REGION:-}" ]] || { log "AWS region unknown"; exit 1; }
log "Using AWS region: $AWS_REGION"

wait_for_docker || exit 1
join_swarm
label_node_with_az

log "Worker setup complete — node enrolled in swarm"
