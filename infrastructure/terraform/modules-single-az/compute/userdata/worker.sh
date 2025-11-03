# ----------------------------------------------------------------------------
# worker.sh — EC2 user data bootstrap for Docker Swarm worker nodes
#
# Provisions Amazon Linux EC2 instance as Docker Swarm worker node.
# Installs Docker, CloudWatch agent, and optional services (worker-manager).
# Swarm join is handled by the worker-manager service.
#
# Environment variables (optional):
#   AWS_REGION, LOG_FILE, PROJECT_NAME, SETUP_USER, CODEDEPLOY_BUCKET_NAME, CERT_MANAGER_PACKAGE_S3_KEY,
#   WORKER_MANAGER_PACKAGE_S3_KEY, SWARM_LOCK_TABLE
#
# Usage: Invoked as EC2 user data by Terraform. Idempotent and safe to re-run.
# ----------------------------------------------------------------------------

set -Eeuo pipefail
shopt -s inherit_errexit || true

readonly LOG_FILE="${LOG_FILE:-/var/log/docker-worker-setup.log}"
readonly PROJECT_NAME="${PROJECT_NAME:-docker-worker}"
readonly SETUP_USER="${SETUP_USER:-ec2-user}"

timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2; }
on_error(){ local ec=$? line=${1:-?}; log "ERROR: line $line exited with code $ec"; exit "$ec"; }
trap 'on_error $LINENO' ERR

pm(){
  local pm_cmd
  pm_cmd=$(command -v dnf || command -v yum || echo "")
  [[ -z "$pm_cmd" ]] && return 1
  case "$1" in
    update)   sudo "$pm_cmd" -y -q update || true ;;
    install)  shift; sudo "$pm_cmd" -y -q install "$@" ;;
  esac
}

imds_get(){
  local path=$1 token
  token=$(curl -X PUT -s --connect-timeout 2 "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || echo "")
  [[ -n "$token" ]] || { log "ERROR: IMDSv2 token unavailable"; return 1; }
  curl -s --connect-timeout 5 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254${path}" 2>/dev/null || true
}
get_aws_region(){ imds_get "/latest/dynamic/instance-identity/document" | jq -r '.region' 2>/dev/null || true; }
get_instance_id(){ imds_get "/latest/meta-data/instance-id"; }

install_docker_stack(){
  pm update
  pm install docker jq awscli || true

  mkdir -p /root/.docker /etc/docker
  local worker_type_label='{"labels": ["worker_type='${WORKER_TYPE}'"] }'
  echo $worker_type_label > /etc/docker/daemon.json

  systemctl enable --now docker
  id "$SETUP_USER" >/dev/null 2>&1 && usermod -aG docker "$SETUP_USER" || true

  command -v docker-credential-ecr-login >/dev/null 2>&1 || pm install amazon-ecr-credential-helper || true

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
    [[ $attempts -le 30 ]] || { log "Docker not ready after ${attempts} attempts"; return 1; }
  done
}

install_cloudwatch_agent(){
  command -v amazon-cloudwatch-agent >/dev/null 2>&1 || pm install amazon-cloudwatch-agent || true
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
          },
          {
            "file_path": "/var/log/worker-manager/worker-manager.log",
            "log_group_name": "/aws/ec2/${PROJECT_NAME}-worker-manager",
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
# Service installation helper
# ----------------------------------------------
install_service_from_s3() {
  local service_name=$1 env_content=$2

  [[ -z "${CODEDEPLOY_BUCKET_NAME:-}" || -z "${service_name}" ]] && \
    { log "ERROR: CODEDEPLOY_BUCKET_NAME or ${service_name} S3 key not set; skipping"; return 0; }

  install -d -m 0755 /usr/local/bin
  command -v unzip >/dev/null 2>&1 || pm install unzip || true

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

install_worker_manager() {
  log "Configuring worker manager service"
  local table_name="${SWARM_LOCK_TABLE:-}"

  [[ -z "$table_name" ]] && { log "ERROR: SWARM_LOCK_TABLE not set"; return 1; }

  local env_content="AWS_REGION=${AWS_REGION}
SWARM_LOCK_TABLE=${table_name}
JOIN_TIMEOUT_SECONDS=${JOIN_TIMEOUT_SECONDS:-300}
WORKER_TYPE=${WORKER_TYPE:-}"

  mkdir -p /var/log/worker-manager
  chown -R ec2-user:ec2-user /var/log/worker-manager
  install_service_from_s3 "worker-manager" "$env_content"
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

install_worker_manager

log "Worker bootstrap complete — worker-manager service will handle swarm join"
