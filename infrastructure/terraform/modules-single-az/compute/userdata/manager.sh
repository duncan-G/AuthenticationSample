# ----------------------------------------------------------------------------
# manager.sh — EC2 user data bootstrap for Docker Swarm manager
#
# Purpose
# - Provision an Amazon Linux EC2 instance as a Docker Swarm manager node.
#
# What this script does
# - Installs Docker, jq, awscli, and the Amazon ECR credential helper; configures
#   Docker to use the credential store for root and (optionally) `SETUP_USER`.
# - Installs and configures the CloudWatch agent to ship this script's log file.
# - Initializes (or ensures) Docker Swarm in manager mode and creates an overlay
#   network (`NETWORK_NAME`, `NETWORK_SUBNET`).
# - Publishes join and network info to AWS Systems Manager Parameter Store under
#   `SSM_PREFIX`: `worker-token`, `manager-ip`, `network-name`.
# - Installs the AWS CodeDeploy agent and labels the node with its AZ for
#   placement constraints.
#
# Inputs/overrides via environment variables
# - `AWS_REGION` (auto-detected if unset), `LOG_FILE`, `SSM_PREFIX`,
#   `NETWORK_NAME`, `NETWORK_SUBNET`, `PROJECT_NAME`, `SETUP_USER`.
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
readonly SSM_PREFIX="${SSM_PREFIX:-/docker/swarm}"
readonly NETWORK_NAME="${NETWORK_NAME:-app-network}"
readonly NETWORK_SUBNET="${NETWORK_SUBNET:-10.20.0.0/16}"
readonly PROJECT_NAME="${PROJECT_NAME:-docker-manager}"
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
pm_cmd(){
  if command -v dnf >/dev/null 2>&1; then echo dnf; elif command -v yum >/dev/null 2>&1; then echo yum; else return 1; fi
}
pm(){
  local pm; pm=$(pm_cmd)
  case "$1" in
    update)   sudo "$pm" -y -q update || true ;;
    install)  shift; sudo "$pm" -y -q install "$@" ;;
    enable)   systemctl enable --now "$2" ;;
  esac
}

# ----------------------------------------------
# IMDS (EC2 metadata) helpers
# ----------------------------------------------
imds_token(){
  curl -X PUT -s --connect-timeout 2 "http://169.254.169.254/latest/api/token" \
       -H "X-aws-ec2-metadata-token-ttl-seconds: 60" || true
}
imds_get(){
  local path=$1 token; token=$(imds_token)
  [[ -n "$token" ]] || { log "ERROR: IMDSv2 token unavailable"; return 1; }
  curl -s --connect-timeout 5 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254${path}" || true
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
  if id "$SETUP_USER" >/dev/null 2>&1; then usermod -aG docker "$SETUP_USER" || true; fi

  # ECR credential helper
  if ! command -v docker-credential-ecr-login >/dev/null 2>&1; then
    pm install amazon-ecr-credential-helper || true
  fi

  # Configure Docker to use ECR creds for root and (optional) SETUP_USER
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
  until docker info >/dev/null 2>&1; do
    sleep 2; attempts=$((attempts+1))
    [[ $attempts -le 30 ]] || { log "Docker not ready after ${attempts} attempts"; return 1; }
  done
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
            "log_group_name": "/aws/ec2/${PROJECT_NAME}-docker-manager",
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
already_in_swarm(){
  local state
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  [[ "$state" == "active" || "$state" == "pending" ]]
}

create_overlay_network(){
  if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    log "Overlay network '$NETWORK_NAME' already exists — skipping"
    return 0
  fi
  docker network create --driver overlay --attachable --subnet "$NETWORK_SUBNET" "$NETWORK_NAME"
  log "Overlay network '$NETWORK_NAME' created"
}

put_param(){
  local name=$1 value=$2
  aws --region "$AWS_REGION" ssm put-parameter \
    --name "$SSM_PREFIX/$name" --type String \
    --value "$value" --overwrite >/dev/null
}

get_param(){
  local name=$1
  aws --region "$AWS_REGION" ssm get-parameter \
    --name "$SSM_PREFIX/$name" \
    --query 'Parameter.Value' --output text 2>/dev/null || true
}

valid_param(){
  local v=$1
  [[ -n "$v" && "$v" != "None" && "$v" != "placeholder" ]]
}

install_codedeploy_agent(){
  if systemctl is-active --quiet codedeploy-agent; then
    log "CodeDeploy agent already running — skip"
    return 0
  fi
  log "Installing CodeDeploy agent …"
  pm update
  pm install ruby wget || true

  local url="https://aws-codedeploy-${AWS_REGION}.s3.${AWS_REGION}.amazonaws.com/latest/install"
  install -d -m 0755 /tmp/codedeploy
  ( cd /tmp/codedeploy && curl -fsSL "$url" -o install_codedeploy && chmod +x install_codedeploy && ./install_codedeploy auto ) || true
  systemctl start codedeploy-agent || true
  log "CodeDeploy agent installed"
}

label_node_with_az(){
  local az node_id
  az=$(get_az || true)
  node_id=$(docker info -f '{{.Swarm.NodeID}}' || true)
  if [[ -n "$az" && -n "$node_id" ]]; then
    docker node update --label-add "az=${az}" "$node_id" || true
  fi
}

# ----------------------------------------------
# DeploymentManager tag (ensure uniqueness)
# ----------------------------------------------
ensure_deployment_manager_tag(){
  local instance_id other_ids current_value
  instance_id=$(get_instance_id || true)
  if [[ -z "$instance_id" ]]; then
    log "Unable to determine instance-id; skipping DeploymentManager tag"
    return 0
  fi

  # Check for any other instance already tagged as DeploymentManager
  other_ids=$(aws --region "$AWS_REGION" ec2 describe-instances \
    --filters "Name=tag-key,Values=DeploymentManager" \
             "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[?InstanceId!='${instance_id}'].InstanceId" \
    --output text 2>/dev/null || true)

  if [[ -n "$other_ids" ]]; then
    log "Another DeploymentManager exists (${other_ids}); skipping tag on ${instance_id}"
    return 0
  fi

  # If this instance already has the tag, do nothing
  current_value=$(aws --region "$AWS_REGION" ec2 describe-tags \
    --filters "Name=resource-id,Values=${instance_id}" "Name=key,Values=DeploymentManager" \
    --query 'Tags[].Value' --output text 2>/dev/null || true)

  if [[ -n "$current_value" ]]; then
    log "Instance ${instance_id} already tagged DeploymentManager=${current_value}"
    return 0
  fi

  # Apply the tag to this instance
  aws --region "$AWS_REGION" ec2 create-tags \
    --resources "$instance_id" \
    --tags "Key=DeploymentManager,Value=true" >/dev/null 2>&1 || {
      log "Warning: failed to create DeploymentManager tag on ${instance_id}"
      return 0
    }
  log "Tagged instance ${instance_id} as DeploymentManager"
}

# ----------------------------------------------
# Certificate Manager service configuration
# ----------------------------------------------
install_certificate_manager(){
  log "Configuring certificate manager service …"

  # Ensure dependencies and target directories
  install -d -m 0755 /usr/local/bin
  if ! command -v flock >/dev/null 2>&1; then pm install util-linux || true; fi

  # Fetch certificate-manager.sh from CodeDeploy S3 bucket when variables are provided
  if [[ -n ${CODEDEPLOY_BUCKET_NAME:-} && -n ${CERT_MANAGER_S3_KEY:-} ]]; then
    log "Downloading s3://${CODEDEPLOY_BUCKET_NAME}/${CERT_MANAGER_S3_KEY} → /usr/local/bin/certificate-manager.sh"
    aws s3 cp "s3://${CODEDEPLOY_BUCKET_NAME}/${CERT_MANAGER_S3_KEY}" \
      /usr/local/bin/certificate-manager.sh \
      --region "${AWS_REGION}" \
      --only-show-errors || log "Warning: Failed to download certificate-manager.sh from S3"
    chmod +x /usr/local/bin/certificate-manager.sh || true
  else
    log "Warning: CODEDEPLOY_BUCKET_NAME or CERT_MANAGER_S3_KEY not set; skipping download"
  fi

  # Install or update systemd unit
  cat >/etc/systemd/system/certificate-manager.service <<'UNIT'
[Unit]
Description=Certificate Manager Daemon
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user

# Writable state directory under /var/lib
StateDirectory=certificate-manager
WorkingDirectory=%S

# Runtime directory for lock file
RuntimeDirectory=certificate-manager
RuntimeDirectoryMode=0755

# Dedicated logs directory under /var/log (owned by service user)
LogsDirectory=certificate-manager
LogsDirectoryMode=0755

# Environment for certificate manager
EnvironmentFile=/etc/certificate-manager.env

ExecStart=/usr/bin/flock -n %t/certificate-manager/instance.lock /usr/local/bin/certificate-manager.sh --daemon

Restart=always
RestartSec=10

SyslogIdentifier=certificate-manager
StandardOutput=journal
StandardError=journal

# Explicitly grant write access to required paths under strict protection
ReadWritePaths=/var/log/certificate-manager /var/lib/certificate-manager

LockPersonality=yes
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only

[Install]
WantedBy=multi-user.target
UNIT

  # Write environment file for the service
  cat >/etc/certificate-manager.env <<ENV
AWS_REGION=${AWS_REGION}
AWS_SECRET_NAME=${AWS_SECRET_NAME}
DOMAIN_NAME=${DOMAIN_NAME}
ENV

  # Ensure systemd is aware of latest units and start the service
  systemctl daemon-reload
  systemctl enable --now certificate-manager.service || true
  log "Certificate manager service enabled"
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

# Tag this instance as the DeploymentManager if none exists yet (best-effort)
ensure_deployment_manager_tag || true

wait_for_docker || exit 1

manager_ip=$(get_local_ip)
[[ -n "$manager_ip" ]] || { log "ERROR: Could not retrieve local IP"; exit 1; }

if already_in_swarm; then
  log "Swarm already initialised"
else
  # Single-shot check: if SSM has manager details, try to join; otherwise init
  existing_manager_token=$(get_param manager-token)
  existing_manager_addr=$(get_param manager-ip)
  if valid_param "$existing_manager_token" && valid_param "$existing_manager_addr"; then
    log "Attempting to join existing swarm manager at $existing_manager_addr"
    if docker swarm join --token "$existing_manager_token" "$existing_manager_addr"; then
      log "Joined existing swarm as manager"
    else
      log "Join failed — initializing a new swarm here"
      docker swarm init --advertise-addr "$manager_ip" >/dev/null
      log "Swarm initialised with advertise-addr $manager_ip"

      manager_addr="${manager_ip}:2377"
      worker_token=$(docker swarm join-token -q worker)
      manager_token=$(docker swarm join-token -q manager)

      log "Persisting initial cluster configuration to SSM"
      put_param "worker-token" "$worker_token"
      put_param "manager-token" "$manager_token"
      put_param "manager-ip" "$manager_addr"
      put_param "network-name" "$NETWORK_NAME"
    fi
  else
    docker swarm init --advertise-addr "$manager_ip" >/dev/null
    log "Swarm initialised with advertise-addr $manager_ip"

    manager_addr="${manager_ip}:2377"
    worker_token=$(docker swarm join-token -q worker)
    manager_token=$(docker swarm join-token -q manager)

    log "Persisting initial cluster configuration to SSM"
    put_param "worker-token" "$worker_token"
    put_param "manager-token" "$manager_token"
    put_param "manager-ip" "$manager_addr"
    put_param "network-name" "$NETWORK_NAME"
  fi
fi

# Ensure overlay network exists (cluster-wide idempotent)
create_overlay_network
install_codedeploy_agent
label_node_with_az

# Install and start certificate manager service
install_certificate_manager

log "Manager initialised at $manager_addr — ready"
