#!/usr/bin/env bash
###############################################################################
# trigger-certificate-renewal.sh
#
# One‑shot certificate renewal for Docker Swarm stacks.
#
# 1.  Starts a transient Swarm service that renews ACME certificates and uploads
#     them to S3. The service *must* exit 0 on success.
# 2.  Downloads the artefacts locally, stores them as Swarm secrets/configs, and
#     hot‑swaps them into a target service.
# 3.  The renewal service generates a new certificate password for each renewal
#     and stores it in AWS Secrets Manager.
#
# Security model ▸ All sensitive values (AWS role, bucket, e‑mail, domains …)
# are distributed as Swarm *secrets*. Non‑sensitive runtime knobs stay in the
# environment.
#
# ── Prerequisites ────────────────────────────────────────────────────────────
# • bash 4+, docker ≥20.10, aws‑cli v2, jq
# ─────────────────────────────────────────────────────────────────────────────
#
# Required AWS Secrets Manager entry (JSON):
# {
#   "APP_NAME"              : "myapp",
#   "CERTIFICATE_STORE"     : "my‑bucket",
#   "DOMAIN_NAME"           : "example.com",
#   "ACME_EMAIL"            : "admin@example.com",
#   "CERTIFICATE_PASSWORD"  : "password",
#   "SUBDOMAIN_NAME_1"      : "api.example.com",
#   "SUBDOMAIN_NAME_2"      : "admin.example.com"
# }
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit

# ── Globals & defaults ───────────────────────────────────────────────────────
readonly LOG_DIR="${LOG_DIR:-/var/log/certificate-manager}"
readonly LOG_FILE="${LOG_FILE:-${LOG_DIR}/trigger-renewal.log}"
readonly LETSENCRYPT_DIR="${LETSENCRYPT_DIR:-/etc/letsencrypt}"
readonly LETSENCRYPT_LOG_DIR="${LETSENCRYPT_LOG_DIR:-/var/log/letsencrypt}"
readonly STAGING_DIR="$(mktemp -d -t cert‑renew.XXXXXXXX)"
readonly RUN_ID="$(date +%Y%m%d%H%M%S)"
readonly SERVICE_NAME="cert-renew-${RUN_ID}"
readonly TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"   # 15 min safety net
readonly WORKER_CONSTRAINT="${WORKER_CONSTRAINT:-node.role==worker}"

# Will be populated later and cleaned up automatically
SECRETS_TO_CLEANUP=()

###############################################################################
# Logging helpers
###############################################################################
_ts()      { date '+%Y-%m-%d %H:%M:%S'; }
log()      { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
fatal()    { log "ERROR: $*"; exit 1; }

###############################################################################
# Cleanup – always runs (EXIT trap)
###############################################################################
cleanup() {
  local rc=$?
  log "🧺 Cleaning up (exit status: $rc)"
  [[ -n "${SERVICE_NAME:-}" ]] && docker service rm -f "$SERVICE_NAME" >/dev/null 2>&1 || true
  if ((${#SECRETS_TO_CLEANUP[@]})); then
    docker secret rm "${SECRETS_TO_CLEANUP[@]}" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
trap 'fatal "command failed at line $LINENO"' ERR

###############################################################################
# Binary checks
###############################################################################
for bin in docker aws jq; do
  command -v "$bin" &>/dev/null || fatal "Required binary not found: $bin"
done

###############################################################################
# Configuration – pulled from AWS Secrets Manager
###############################################################################
log "🔐 Fetching secret \"$AWS_SECRET_NAME\" from AWS Secrets Manager"

secret_json="$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_NAME" \
               --query SecretString --output text)" || \
  fatal "Failed to retrieve secret \"$AWS_SECRET_NAME\""

APP_NAME="${APP_NAME:-$(jq -r '.APP_NAME' <<<"$secret_json")}"
CERTIFICATE_STORE="${CERTIFICATE_STORE:-$(jq -r '.CERTIFICATE_STORE' <<<"$secret_json")}"
# Extract subdomain names from SUBDOMAIN_NAME_1, SUBDOMAIN_NAME_2, etc.
SUBDOMAIN_NAMES="$(
  jq -r 'to_entries | map(select(.key | startswith("SUBDOMAIN_NAME_"))) | sort_by(.key) | .[].value' <<<"$secret_json" \
  | awk '{$1=$1};1' | paste -sd, -
)"
ACME_EMAIL="${ACME_EMAIL:-$(jq -r '.ACME_EMAIL' <<<"$secret_json")}"
AWS_REGION="${AWS_REGION:-$(jq -r '.AWS_REGION' <<<"$secret_json")}"

for v in APP_NAME CERTIFICATE_STORE ACME_EMAIL; do
  [[ -z "${!v}" || ${!v} == "null" ]] && fatal "\"$v\" missing in secret or env"
  readonly "$v"
done

readonly SUBDOMAIN_NAMES

# Create domain array from comma-separated subdomain names
IFS=',' read -r -a DOMAIN_ARRAY <<< "$SUBDOMAIN_NAMES"
readonly DOMAIN_ARRAY

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
RENEWAL_THRESHOLD_DAYS="${RENEWAL_THRESHOLD_DAYS:-10}"
AWS_ROLE_NAME="${AWS_ROLE_NAME:-${APP_NAME}-ec2-public-instance-role}"
RENEWAL_IMAGE="${RENEWAL_IMAGE:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/auth-sample/certbot:latest}"

# Services by domain mapping (JSON format: {"domain1": ["service1", "service2"], "domain2": ["service3"]})
SERVICES_BY_DOMAIN_JSON="${SERVICES_BY_DOMAIN:-}"

# Parse services by domain from JSON or create empty mapping
if [[ -n "$SERVICES_BY_DOMAIN_JSON" ]]; then
  # Validate JSON format
  if ! jq empty <<< "$SERVICES_BY_DOMAIN_JSON" 2>/dev/null; then
    fatal "Invalid JSON format in SERVICES_BY_DOMAIN: $SERVICES_BY_DOMAIN_JSON"
  fi
  log "📋 Services by domain configuration: $SERVICES_BY_DOMAIN_JSON"
else
  SERVICES_BY_DOMAIN_JSON="{}"
  log "ℹ️  No services by domain configuration provided"
fi

readonly CERT_OUTPUT_DIR="${CERT_OUTPUT_DIR:-/certs}"
readonly CERT_SECRET_TARGET="${CERT_SECRET_TARGET:-cert.pem}"
readonly KEY_SECRET_TARGET="${KEY_SECRET_TARGET:-cert.key}"
readonly FULLCHAIN_SECRET_TARGET="${FULLCHAIN_SECRET_TARGET:-fullchain.pem}"
readonly PFX_SECRET_TARGET="${PFX_SECRET_TARGET:-cert.pfx}"

###############################################################################
# Create transient Docker secrets for configuration
###############################################################################
log "🔐 Creating runtime Docker secrets"
create_secret() {
  local name=$1 value=$2
  local id
  id="$(printf '%s' "$value" | docker secret create "$name" -)" || fatal "Unable to create secret $name"
  SECRETS_TO_CLEANUP+=("$name")
  printf '%s' "$id"
}

create_secret aws_role_name_${RUN_ID}     "$AWS_ROLE_NAME"
create_secret certificate_store_${RUN_ID} "$CERTIFICATE_STORE"
create_secret acme_email_${RUN_ID}        "$ACME_EMAIL"
create_secret domain_names_${RUN_ID}      "$SUBDOMAIN_NAMES"
log "✅ Runtime secrets ready"

###############################################################################
# Authenticate to ECR on all active instances
###############################################################################
log "🔐 Authenticating to ECR repository on all active instances"

# Get current instance ID
CURRENT_INSTANCE_ID=""
if TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null); then
  CURRENT_INSTANCE_ID="$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo '')"
fi

log "🔍 Current instance ID: ${CURRENT_INSTANCE_ID:-'unknown'}"

# Get all active instance IDs
log "📋 Getting all active instance IDs"
ALL_INSTANCE_IDS=($(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)) || fatal "Failed to get active instance IDs"

if ((${#ALL_INSTANCE_IDS[@]} == 0)); then
  fatal "No active instances found for ECR authentication"
fi

log "🔍 Found ${#ALL_INSTANCE_IDS[@]} active instance(s): ${ALL_INSTANCE_IDS[*]}"

# Authenticate to ECR on each instance
for instance_id in "${ALL_INSTANCE_IDS[@]}"; do
  log "🔐 Authenticating ECR on instance: $instance_id"
  
  # Check if this is the current instance
  if [[ "$instance_id" == "$CURRENT_INSTANCE_ID" ]]; then
    log "🔄 Running ECR authentication directly on current instance: $instance_id"
    
    # Run command directly on current instance with error capture
    if ! ecr_output=$(aws ecr get-login-password --region "$AWS_REGION" 2>&1); then
      log "❌ AWS ECR get-login-password failed on current instance: $instance_id"
      log "Error output: $ecr_output"
      fatal "ECR authentication failed on current instance: $instance_id"
    fi
    
    if ! docker_output=$(echo "$ecr_output" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" 2>&1); then
      log "❌ Docker login failed on current instance: $instance_id"
      log "Docker error output: $docker_output"
      fatal "ECR authentication failed on current instance: $instance_id"
    fi
    
    log "✅ ECR authentication successful on current instance: $instance_id"
  else
    log "🔄 Running ECR authentication via SSM on remote instance: $instance_id"
    
    # Create SSM command to authenticate to ECR with better error handling
    ssm_command="set -e; echo 'Starting ECR authentication on instance $instance_id...'; echo 'AWS Region: $AWS_REGION'; echo 'ECR Repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com'; aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com; echo 'ECR authentication completed successfully on instance $instance_id'"
    
    # Send command via SSM
    command_id=$(aws ssm send-command \
      --region "$AWS_REGION" \
      --instance-ids "$instance_id" \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=[\"$ssm_command\"]" \
      --query 'Command.CommandId' \
      --output text) || fatal "Failed to send SSM command to instance $instance_id"
    
    log "⏳ Waiting for SSM command completion on $instance_id"
    
    # Wait for command completion
    while true; do
      status=$(aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$command_id" \
        --instance-id "$instance_id" \
        --query 'Status' \
        --output text) || fatal "Failed to get command status for $instance_id"
      
      case "$status" in
        "Success")
          log "✅ ECR authentication successful on $instance_id"
          break
          ;;
        "Failed"|"Cancelled"|"TimedOut")
          log "❌ SSM command failed on $instance_id with status: $status"
          
          # Get detailed command output for debugging
          command_details=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$command_id" \
            --instance-id "$instance_id" 2>&1 || echo "Failed to get command details")
          
          log "Command details for $instance_id:"
          log "$command_details"
          
          # Extract and log the actual error output
          if command_output=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'StandardErrorContent' \
            --output text 2>/dev/null); then
            if [[ -n "$command_output" ]]; then
              log "Error output from $instance_id:"
              log "$command_output"
            fi
          fi
          
          if command_output=$(aws ssm get-command-invocation \
            --region "$AWS_REGION" \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'StandardOutputContent' \
            --output text 2>/dev/null); then
            if [[ -n "$command_output" ]]; then
              log "Standard output from $instance_id:"
              log "$command_output"
            fi
          fi
          
          fatal "ECR authentication failed on $instance_id with status: $status"
          ;;
        *)
          log "⏳ Command still running on $instance_id (status: $status)"
          sleep 5
          ;;
      esac
    done
  fi
done

log "✅ ECR authentication completed on all active instances"

###############################################################################
# Launch renewal task
###############################################################################
log "▶️  Launching renewal service: $SERVICE_NAME"
service_id="$(docker service create \
  --quiet \
  --name "$SERVICE_NAME" \
  --constraint "$WORKER_CONSTRAINT" \
  --restart-condition none \
  --stop-grace-period 5m \
  --mount type=bind,source="$LOG_DIR",target="$LOG_DIR" \
  --mount type=bind,source="$LETSENCRYPT_DIR",target="$LETSENCRYPT_DIR" \
  --mount type=bind,source="$LETSENCRYPT_LOG_DIR",target="$LETSENCRYPT_LOG_DIR" \
  --env RUN_ID="$RUN_ID" \
  --env CERT_PREFIX="$APP_NAME" \
  --env RENEWAL_THRESHOLD_DAYS="$RENEWAL_THRESHOLD_DAYS" \
  --secret source=aws_role_name_${RUN_ID},target=AWS_ROLE_NAME \
  --secret source=certificate_store_${RUN_ID},target=CERTIFICATE_STORE \
  --secret source=acme_email_${RUN_ID},target=ACME_EMAIL \
  --secret source=domain_names_${RUN_ID},target=DOMAINS_NAMES \
  --env AWS_SECRET_NAME="$AWS_SECRET_NAME" \
  "$RENEWAL_IMAGE")" || fatal "Unable to create service"

###############################################################################
# Wait for the task to finish – with timeout
###############################################################################
log "⏳ Waiting for completion (timeout ${TIMEOUT_SECONDS}s)"
end=$((SECONDS+TIMEOUT_SECONDS))
while true; do
  state="$(docker service ps --no-trunc --filter desired-state=shutdown --format '{{.CurrentState}}' "$service_id" | head -n1)" || true
  case "$state" in
    *\ running)   ;; # still working
    *\ "Complete") break ;;
    *\ "Failed"*)  docker service logs "$service_id" || true; fatal "Renewal task failed" ;;
    *)             ;; # not started yet
  esac
  (( SECONDS < end )) || fatal "Timeout waiting for renewal task"
  sleep 3
done

#------------------------------------------------------------------------------
# Download artefacts & publish secrets
#------------------------------------------------------------------------------
log "📥 Pulling certificates into $STAGING_DIR …"

# Download per‑domain artefacts
for domain in "${DOMAIN_ARRAY[@]}"; do
  s3_prefix="$APP_NAME/$RUN_ID/$domain/"
  dest="$STAGING_DIR/$domain"
  mkdir -p "$dest"
  log "   ↳ $domain"
  if ! aws s3 cp "s3://$CERTIFICATE_STORE/$s3_prefix" "$dest/" --recursive --only-show-errors; then
    fatal "Download failed for $domain" 
  fi
  [[ -s "$dest/cert.pem" ]] || log "⚠️  No cert.pem found for $domain (may be new sub‑domain?)"
done

# Flatten file‑tree & create secrets
log "🔐 Publishing Swarm secrets …"
declare -A NEW_SECRETS=()
for domain in "${DOMAIN_ARRAY[@]}"; do
  src="$STAGING_DIR/$domain"
  [[ -d "$src" ]] || continue
  for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
    [[ -f "$src/$f" ]] || continue
    flat="${domain//./-}-$f"        # dots → dashes (Swarm secret name safe)
    cp -p "$src/$f" "$STAGING_DIR/$flat"
    secret_name="$flat-$RUN_ID"
    docker secret create "$secret_name" "$STAGING_DIR/$flat" >/dev/null || fatal "Cannot create secret $secret_name"
    NEW_SECRETS["$domain/$f"]="$secret_name"
    SECRETS_TO_CLEANUP+=("$secret_name")
  done
done
log "   → ${#NEW_SECRETS[@]} new secrets ready."

#------------------------------------------------------------------------------
# Hot‑swap secrets into services
#------------------------------------------------------------------------------
if [[ -n "${SERVICES_BY_DOMAIN:-}" && "$SERVICES_BY_DOMAIN" != "{}" ]]; then
  log "🔄 Rotating secrets in target services …"
  jq -e empty <<<"$SERVICES_BY_DOMAIN" || fatal "SERVICES_BY_DOMAIN is not valid JSON."
  while IFS= read -r domain; do
    mapfile -t services < <(jq -r --arg d "$domain" '.[$d][]' <<< "$SERVICES_BY_DOMAIN")
    ((${#services[@]})) || continue
    for svc in "${services[@]}"; do
      log "   ↻ $svc ← $domain"
      args=(docker service update --quiet
            --secret-rm cert.pem
            --secret-rm privkey.pem
            --secret-rm fullchain.pem
            --secret-rm cert.pfx)
      for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
        sec="${NEW_SECRETS[$domain/$f]:-}"
        [[ -n "$sec" ]] && args+=(--secret-add "source=$sec,target=$f")
      done
      args+=("$svc")
      "${args[@]}" >/dev/null || fatal "Failed to update $svc"
    done
  done < <(jq -r 'keys[]' <<< "$SERVICES_BY_DOMAIN")
else
  log "ℹ️  No SERVICES_BY_DOMAIN mapping provided — skipping service updates."
fi

#------------------------------------------------------------------------------
# Report
#------------------------------------------------------------------------------
log "🎉 Certificate rotation complete (domains: ${DOMAIN_ARRAY[*]})"
exit 0
