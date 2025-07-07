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
log()      { printf '[ %s ] TRIGGER: %s\n' "$(_ts)" "$*" >&2; }
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
# Wait for Docker Swarm to be initialized
###############################################################################
log "🔍 Checking Docker Swarm initialization..."

already_in_swarm() {
  local state
  state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")
  [[ "$state" == "active" || "$state" == "pending" ]]
}

# Default timeout for swarm initialization (5 minutes)
readonly SWARM_INIT_TIMEOUT="${SWARM_INIT_TIMEOUT:-300}"
readonly SWARM_CHECK_INTERVAL="${SWARM_CHECK_INTERVAL:-10}"

swarm_init_timeout=$((SECONDS + SWARM_INIT_TIMEOUT))

while ((SECONDS < swarm_init_timeout)); do
    # Check if Docker is running and swarm is initialized
    if already_in_swarm; then
    log "✅ Docker Swarm is initialized and ready"
    break
  else
    log "⏳ Waiting for Docker Swarm initialization... (${SWARM_INIT_TIMEOUT}s timeout)"
    sleep "$SWARM_CHECK_INTERVAL"
  fi
done

# Final check after timeout
if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active\|pending"; then
  fatal "Docker Swarm initialization timeout after ${SWARM_INIT_TIMEOUT}s. Swarm must be initialized before certificate renewal can proceed."
fi

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
# ECR authentication is now handled by the ECR credential helper
###############################################################################
log "🔐 ECR authentication is handled by the ECR credential helper"

###############################################################################
# Launch renewal task
###############################################################################
log "▶️  Launching renewal service: $SERVICE_NAME"
log "📋 View service logs in CloudWatch: stream: $SERVICE_NAME. Log group: /aws/ec2/$APP_NAME-certificate-manager"

readonly WORKER_LOG_DIR="${WORKER_LOG_DIR:-/var/log/certificate-manager}"
service_id="$(docker service create \
  --detach \
  --quiet \
  --with-registry-auth \
  --name "$SERVICE_NAME" \
  --constraint "$WORKER_CONSTRAINT" \
  --restart-condition none \
  --stop-grace-period 5m \
  --mount type=bind,source="$WORKER_LOG_DIR",target="$WORKER_LOG_DIR" \
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
  --log-driver awslogs \
  --log-opt awslogs-region="$AWS_REGION" \
  --log-opt awslogs-group="/aws/ec2/$APP_NAME-certificate-manager" \
  --log-opt awslogs-stream="$SERVICE_NAME" \
  --log-opt mode=non-blocking \
  "$RENEWAL_IMAGE" --staging)" || fatal "Unable to create service"

###############################################################################
# Wait for the task to finish – with timeout
###############################################################################
log "⏳ Waiting for completion (timeout ${TIMEOUT_SECONDS}s)"
log "Service ID: $service_id"
end=$((SECONDS+TIMEOUT_SECONDS))
while true; do
  state="$(docker service ps --no-trunc --filter desired-state=shutdown --format '{{.CurrentState}}' "$service_id" | head -n1)" || true
  
  # Log progress every poll (3 seconds)
  elapsed=$((SECONDS - (end - TIMEOUT_SECONDS)))
  remaining=$((end - SECONDS))
  log "⏳ Still waiting... (${elapsed}s elapsed, ${remaining}s remaining) - Service state: $state"
  
  case "$state" in
    *\ running)   ;; # still working
    *\ "Complete"*) log "✅ Service completed successfully"; break ;;
    *\ "Failed"*)  fatal "Renewal task failed" ;;
    *)             ;; # not started yet
  esac
  (( SECONDS < end )) || fatal "Timeout waiting for renewal task"
  sleep 3
done

#------------------------------------------------------------------------------
# Check renewal status and download artefacts
#------------------------------------------------------------------------------
log "📋 Checking renewal status from S3..."

# Download the renewal status file
status_file="$STAGING_DIR/renewal-status.json"
if ! aws s3 cp "s3://$CERTIFICATE_STORE/$APP_NAME/$RUN_ID/renewal-status.json" "$status_file" --only-show-errors; then
  log "⚠️  No renewal status file found - assuming no renewal occurred"
  RENEWAL_OCCURRED=false
  RENEWED_DOMAINS=()
else
  # Parse the status file
  if jq -e . "$status_file" >/dev/null 2>&1; then
    RENEWAL_OCCURRED=$(jq -r '.renewal_occurred' "$status_file")
    RENEWED_DOMAINS=($(jq -r '.renewed_domains[]?' "$status_file"))
    log "📊 Renewal status: occurred=$RENEWAL_OCCURRED, domains=${RENEWED_DOMAINS[*]}"
  else
    log "⚠️  Invalid renewal status file - assuming no renewal occurred"
    RENEWAL_OCCURRED=false
    RENEWED_DOMAINS=()
  fi
fi

# Only proceed with certificate processing if renewal occurred
if [[ "$RENEWAL_OCCURRED" == "true" && ${#RENEWED_DOMAINS[@]} -gt 0 ]]; then
  log "📥 Pulling renewed certificates into $STAGING_DIR …"
  
  # Download per‑domain artefacts for renewed domains only
  for domain in "${RENEWED_DOMAINS[@]}"; do
    s3_prefix="$APP_NAME/$RUN_ID/$domain/"
    dest="$STAGING_DIR/$domain"
    mkdir -p "$dest"
    log "   ↳ $domain"
    if ! aws s3 cp "s3://$CERTIFICATE_STORE/$s3_prefix" "$dest/" --recursive --only-show-errors; then
      fatal "Download failed for $domain" 
    fi
    [[ -s "$dest/cert.pem" ]] || log "⚠️  No cert.pem found for $domain (may be new sub‑domain?)"
  done
else
  log "ℹ️  No certificates were renewed - checking for missing secrets in Swarm"
  MISSING_SECRETS=()
  for domain in "${DOMAIN_ARRAY[@]}"; do
    for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
      secret_name="${domain//./-}-$f-$RUN_ID"
      if ! docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log "   ↳ Missing secret: $secret_name"
        MISSING_SECRETS+=("$domain/$f")
      fi
    done
  done
  if [[ ${#MISSING_SECRETS[@]} -eq 0 ]]; then
    log "✅ All required secrets already exist in Swarm - no action needed"
    log "🎉 Certificate check complete (no renewal needed)"
    exit 0
  fi
  # Download and create missing secrets
  log "📥 Downloading certs from S3 for missing secrets..."
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
  log "🔐 Creating missing Swarm secrets ..."
  declare -A NEW_SECRETS=()
  for domain in "${DOMAIN_ARRAY[@]}"; do
    src="$STAGING_DIR/$domain"
    [[ -d "$src" ]] || continue
    for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
      flat="${domain//./-}-$f"
      secret_name="$flat-$RUN_ID"
      if ! docker secret inspect "$secret_name" >/dev/null 2>&1 && [[ -f "$src/$f" ]]; then
        cp -p "$src/$f" "$STAGING_DIR/$flat"
        docker secret create "$secret_name" "$STAGING_DIR/$flat" >/dev/null || fatal "Cannot create secret $secret_name"
        NEW_SECRETS["$domain/$f"]="$secret_name"
        SECRETS_TO_CLEANUP+=("$secret_name")
      fi
    done
  done
  log "   → ${#NEW_SECRETS[@]} new secrets created."
  # Update services for domains where secrets were added
  if [[ -n "${SERVICES_BY_DOMAIN:-}" && "$SERVICES_BY_DOMAIN" != "{}" ]]; then
    log "🔄 Rotating secrets in target services for domains with new secrets …"
    jq -e empty <<<"$SERVICES_BY_DOMAIN" || fatal "SERVICES_BY_DOMAIN is not valid JSON."
    for domain in "${DOMAIN_ARRAY[@]}"; do
      mapfile -t services < <(jq -r --arg d "$domain" '.[$d][]?' <<< "$SERVICES_BY_DOMAIN")
      ((${#services[@]})) || continue
      for svc in "${services[@]}"; do
        log "   ↻ $svc ← $domain"
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
    done
  else
    log "ℹ️  No Services found to update — skipping service updates."
  fi
  log "🎉 Certificate check complete (secrets synced)"
  exit 0
fi

#------------------------------------------------------------------------------
# Report
#------------------------------------------------------------------------------
log "🎉 Certificate rotation complete (domains: ${DOMAIN_ARRAY[*]})"
exit 0
