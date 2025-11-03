# ----------------------------------------------------------------------------
# manager.sh — EC2 user data bootstrap for Docker Swarm manager
#
# Purpose
# - Provision an Amazon Linux EC2 instance as a Docker Swarm manager node.
#
# What this script does
# - Installs Docker, jq, awscli, and the Amazon ECR credential helper; configures
#   Docker to use the credential store for root and (optionally) `SETUP_USER`.
# - Installs and configures the CloudWatch agent to ship logs from:
#   - This script's log file
#   - leader-manager service logs
#   - certificate-manager service logs
# - Installs the AWS CodeDeploy agent.
# - Tags the instance as DeploymentManager if it's the first running instance
#   with that tag.
# - Installs certificate-manager service from S3 (manages SSL certificates).
# - Installs leader-manager service from S3, which handles Docker Swarm
#   initialization and join operations using DynamoDB for leader election.
#   The cluster_name is set to the EC2 instance ID.
#
# Inputs/overrides via environment variables
# - `AWS_REGION` (auto-detected if unset), `LOG_FILE`, `PROJECT_NAME`, `SETUP_USER`,
#   `CODEDEPLOY_BUCKET_NAME`, `AWS_SECRET_NAME`, `DOMAIN_NAME`, `SWARM_LOCK_TABLE`.
#
# Usage
# - Invoked as EC2 user data by Terraform for instances tagged `Role=manager`,
#   and/or executed via SSM associations. Designed to be idempotent and safe to
#   re-run.
# ----------------------------------------------------------------------------

set -Eeuo pipefail
shopt -s inherit_errexit || true

# ----------------------------------------------
# Globals (override with env vars if needed)
# ----------------------------------------------
readonly LOG_FILE="${LOG_FILE:-/var/log/docker-manager-setup.log}"
readonly PROJECT_NAME="${PROJECT_NAME:-docker-manager}"
readonly ENV="${ENV:-}"
readonly SETUP_USER="${SETUP_USER:-ec2-user}"

# ----------------------------------------------
# Logging & error handling
# ----------------------------------------------
timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2; }

on_error(){
  local ec=$? line=${1:-?}
  log "ERROR: line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR

# ----------------------------------------------
# Package manager helpers
# ----------------------------------------------
pm(){
  local pm_cmd
  pm_cmd=$(command -v dnf || command -v yum || echo "")
  [[ -z "$pm_cmd" ]] && return 1
  case "$1" in
    update)   sudo "$pm_cmd" -y -q update || true ;;
    install)  shift; sudo "$pm_cmd" -y -q install "$@" ;;
    enable)   systemctl enable --now "$2" ;;
  esac
}

# ----------------------------------------------
# IMDS (EC2 metadata) helpers
# ----------------------------------------------
imds_get(){
  local path=$1 token
  token=$(curl -X PUT -s --connect-timeout 2 "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
  [[ -n "$token" ]] || { log "ERROR: IMDSv2 token unavailable"; return 1; }
  curl -s --connect-timeout 5 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254${path}" 2>/dev/null || true
}
get_aws_region(){ imds_get "/latest/dynamic/instance-identity/document" | jq -r '.region' 2>/dev/null || true; }
get_local_ip(){  imds_get "/latest/meta-data/local-ipv4"; }
get_az(){        imds_get "/latest/meta-data/placement/availability-zone"; }
get_instance_id(){ imds_get "/latest/meta-data/instance-id"; }

# ----------------------------------------------
# Docker & ECR creds
# ----------------------------------------------
install_docker_stack(){
  pm update
  pm install docker jq awscli openssl || true
  systemctl enable --now docker
  id "$SETUP_USER" >/dev/null 2>&1 && usermod -aG docker "$SETUP_USER" || true

  command -v docker-credential-ecr-login >/dev/null 2>&1 || pm install amazon-ecr-credential-helper || true

  # Configure Docker ECR creds
  mkdir -p /root/.docker /etc/docker
  echo '{"credsStore":"ecr-login"}' > /root/.docker/config.json
  echo '{"credsStore":"ecr-login"}' > /etc/docker/config.json

  if id "$SETUP_USER" >/dev/null 2>&1; then
    mkdir -p ~"$SETUP_USER"/.docker
    echo '{"credsStore":"ecr-login"}' > ~"$SETUP_USER"/.docker/config.json
    chown -R "$SETUP_USER:$SETUP_USER" ~"$SETUP_USER"/.docker
  fi
}

wait_for_docker(){
  local attempts=0
  until docker info >/dev/null 2>&1; do
    sleep 2
    ((attempts++))
    ((attempts >= 30)) && { log "Docker not ready after $attempts attempts"; return 1; }
  done
}

wait_for_swarm(){
  local attempts=0
  log "Waiting for node to join swarm..."
  until docker info 2>/dev/null | grep -q "Swarm: active"; do
    sleep 5
    ((attempts++))
    ((attempts >= 60)) && { log "Node not in swarm after $((attempts * 5)) seconds"; return 1; }
    log "Swarm not active yet (attempt $attempts/60)..."
  done
  log "Node is now in swarm"
}

# ----------------------------------------------
# CloudWatch agent
# ----------------------------------------------
install_cloudwatch_agent(){
  if ! command -v amazon-cloudwatch-agent >/dev/null 2>&1; then
    pm install amazon-cloudwatch-agent || true
  fi
  mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
  cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$LOG_FILE",
            "log_group_name": "/aws/ec2/${PROJECT_NAME}${ENV:+-${ENV}}-docker-manager",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/leader-manager/leader-manager.log",
            "log_group_name": "/aws/ec2/${PROJECT_NAME}${ENV:+-${ENV}}-leader-manager",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S"
          },
          {
            "file_path": "/var/log/certificate-manager/certificate-manager.log",
            "log_group_name": "/aws/ec2/${PROJECT_NAME}${ENV:+-${ENV}}-certificate-manager",
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


install_codedeploy_agent(){
  systemctl is-active --quiet codedeploy-agent && { log "CodeDeploy agent already running"; return 0; }
  log "Installing CodeDeploy agent"
  pm update
  pm install ruby wget || true
  local url="https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install"
  install -d -m 0755 /tmp/codedeploy
  (cd /tmp/codedeploy && curl -fsSL "$url" -o install_codedeploy && chmod +x install_codedeploy && ./install_codedeploy auto) || true
  systemctl start codedeploy-agent || true
}

# ----------------------------------------------
# DeploymentManager tag (ensure uniqueness)
# ----------------------------------------------
ensure_deployment_manager_tag(){
  local instance_id other_ids current_value
  instance_id=$(get_instance_id || true)
  [[ -z "$instance_id" ]] && { log "Unable to determine instance-id; skipping DeploymentManager tag"; return 0; }

  other_ids=$(aws --region "$AWS_REGION" ec2 describe-instances \
    --filters "Name=tag-key,Values=DeploymentManager" \
             "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[?InstanceId!='${instance_id}'].InstanceId" \
    --output text 2>/dev/null || true)

  [[ -n "$other_ids" ]] && { log "Another DeploymentManager exists (${other_ids}); skipping"; return 0; }

  current_value=$(aws --region "$AWS_REGION" ec2 describe-tags \
    --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=DeploymentManager" \
    --query 'Tags[].Value' --output text 2>/dev/null || true)

  [[ -n "$current_value" ]] && { log "Instance ${instance_id} already tagged DeploymentManager=${current_value}"; return 0; }

  aws --region "$AWS_REGION" ec2 create-tags \
    --resources "$instance_id" \
    --tags "Key=DeploymentManager,Value=true" >/dev/null 2>&1 && \
    log "Tagged instance ${instance_id} as DeploymentManager" || \
    log "Warning: failed to create DeploymentManager tag"
}

# ----------------------------------------------
# Service installation helper
# ----------------------------------------------
install_service_from_s3() {
  local service_name=$1 env_content=$2

  [[ -z "${CODEDEPLOY_BUCKET_NAME:-}" || -z "${service_name}" ]] && \
    { log "ERROR: CODEDEPLOY_BUCKET_NAME or ${service_name} S3 key not set; skipping"; return 0; }

  install -d -m 0755 /usr/local/bin
  command -v unzip >/dev/null 2>&1 || pm install unzip || true
  [[ "$service_name" == "certificate-manager" ]] && \
    command -v flock >/dev/null 2>&1 || pm install util-linux || true

  local tmp_dir="$(mktemp -d /tmp/${service_name}.XXXX)"
  local package_zip="$tmp_dir/${service_name}.zip"
  local extract_dir="$tmp_dir/extract"

  log "Downloading s3://${CODEDEPLOY_BUCKET_NAME}/infrastructure/${service_name}.zip"
  aws s3 cp "s3://${CODEDEPLOY_BUCKET_NAME}/infrastructure/${service_name}.zip" "$package_zip" \
    --region "$AWS_REGION" --only-show-errors || \
    { log "ERROR: download failed"; rm -rf "$tmp_dir"; return 1; }

  mkdir -p "$extract_dir"
  unzip -o -q "$package_zip" -d "$extract_dir" || \
    { log "ERROR: unzip failed"; rm -rf "$tmp_dir"; return 1; }

  local src_script src_service src_timer
  src_script=$(find "$extract_dir" -maxdepth 2 -type f -name "${service_name}.sh" | head -n1 || true)
  src_service=$(find "$extract_dir" -maxdepth 2 -type f -name "${service_name}.service" | head -n1 || true)
  src_timer=$(find "$extract_dir" -maxdepth 2 -type f -name "${service_name}.timer" | head -n1 || true)

  [[ -z "$src_script" || -z "$src_service" || -z "$src_timer" ]] && \
    { log "ERROR: package missing ${service_name}.sh or .service"; rm -rf "$tmp_dir"; return 1; }

  log "Installing ${service_name} script and service"
  install -m 0755 "$src_script" "/usr/local/bin/${service_name}.sh"
  install -m 0644 "$src_service" "/etc/systemd/system/${service_name}.service"
  install -m 0644 "$src_timer" "/etc/systemd/system/${service_name}.timer"

  [[ -n "$env_content" ]] && echo "$env_content" > "/etc/${service_name}.env"

  systemctl daemon-reload
  systemctl enable --now "${service_name}.timer" || true

  rm -rf "$tmp_dir"
}

install_certificate_manager() {
  log "Configuring certificate manager service"
  local env_content="AWS_REGION=${AWS_REGION}
AWS_SECRET_NAME=${AWS_SECRET_NAME}
DOMAIN_NAME=${DOMAIN_NAME}"
mkdir -p /var/log/certificate-manager
chown -R ec2-user:ec2-user /var/log/certificate-manager
  install_service_from_s3 "certificate-manager" "$env_content"
}

install_leader_manager() {
  log "Configuring leader manager service"
  local table_name="${SWARM_LOCK_TABLE:-}"
  local iid

  iid=$(get_instance_id || true)
  [[ -z "$iid" ]] && { log "ERROR: Unable to determine instance-id"; return 1; }

  [[ -z "$table_name" ]] && { log "ERROR: SWARM_LOCK_TABLE not set"; return 1; }

  local env_content="AWS_REGION=${AWS_REGION}
SWARM_LOCK_TABLE=${table_name}"
  mkdir -p /var/log/leader-manager
  chown -R ec2-user:ec2-user /var/log/leader-manager
  install_service_from_s3 "leader-manager" "$env_content"
}

# ----------------------------------------------
# Main
# ----------------------------------------------
log "Bootstrap initiated — Docker Swarm manager setup starting"

install_docker_stack
install_cloudwatch_agent

readonly AWS_REGION="${AWS_REGION:-$(get_aws_region)}"
[[ -n "${AWS_REGION:-}" ]] || { log "AWS region unknown"; exit 1; }
log "Using AWS region: $AWS_REGION"

ensure_deployment_manager_tag || true
wait_for_docker || exit 1
configure_docker_daemon || exit 1

log "Swarm join/init will be handled by leader-manager service"

install_codedeploy_agent
install_leader_manager

wait_for_swarm || exit 1
install_certificate_manager

log "Manager bootstrap complete — leader-manager service will handle swarm join"
