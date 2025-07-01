#!/usr/bin/env bash
###############################################################################
# trigger-certificate-renewal.sh
#
# • Starts a one-shot Swarm service that renews certificates and pushes them
#   to S3 (the container's ENTRYPOINT must exit 0 on success).
# • Downloads the fresh certs, turns them into Swarm secrets / configs, and
#   hot-swaps those into a consumer service.
#
# ---------------------------------------------------------------------------
# Environment variables:
#   AWS_SECRET_NAME            Name of the secret in AWS Secrets Manager (REQUIRED)
#                              The secret must contain: app_name, s3_bucket, domain, 
#                              internal_domain, email
#
#   CERT_PREFIX                Folder prefix in the bucket (default: cert)
#   WILDCARD                   "true" → request *.DOMAIN in addition (default: false)
#   RENEWAL_THRESHOLD_DAYS     Renew if cert expires within N days (default: 30)
#
#   DOCKER_IMAGE_NAME / TAG    Image that performs the renewal
#   CONSUMER_SERVICE           Service that needs the secrets
#
#   *_SECRET_TARGET            Mount points inside CONSUMER_SERVICE
#
#   WORKER_CONSTRAINT          Node label to pin the one-shot task
#
#   LOG_DIR                    Directory for log files (default: /var/log)
#   LOG_FILE                   Log file name (default: certificate-renewal.log)
#
# ---------------------------------------------------------------------------
# Requires: docker, aws-cli
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit

# ── Logging helpers ──────────────────────────────────────────────────────────
timestamp()  { date '+%Y-%m-%d %H:%M:%S'; }
log()        { printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2; }
fatal()      { log "ERROR: $*"; exit 1; }
trap 'fatal "Line $LINENO exited with status $?"' ERR

# ── AWS Secrets Manager integration ──────────────────────────────────────────
readonly AWS_SECRET_NAME="${AWS_SECRET_NAME}"

fetch_secrets_from_aws() {
  log "🔐 Fetching configuration from AWS Secrets Manager: $AWS_SECRET_NAME"
  
  # Check if AWS CLI is available
  command -v aws &>/dev/null || fatal "AWS CLI not found"
  
  # Fetch the secret
  local secret_json
  local aws_error
  secret_json=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_NAME" --query SecretString --output text 2>&1) || {
    aws_error="$secret_json"
    fatal "Failed to fetch secret '$AWS_SECRET_NAME' from AWS Secrets Manager: $aws_error"
  }
  
  # Parse JSON and export variables
  # Expected JSON structure:
  # {
  #   "app_name": "myapp",
  #   "s3_bucket": "my-bucket",
  #   "domain": "example.com", 
  #   "internal_domain": "internal.example.com",
  #   "email": "admin@example.com"
  # }
  
  # Extract values using jq
  export TF_APP_NAME="${TF_APP_NAME:-$(echo "$secret_json" | jq -r '.app_name // empty')}"
  export S3_BUCKET="${S3_BUCKET:-$(echo "$secret_json" | jq -r '.s3_bucket // empty')}"
  export DOMAIN="${DOMAIN:-$(echo "$secret_json" | jq -r '.domain // empty')}"
  export INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-$(echo "$secret_json" | jq -r '.internal_domain // empty')}"
  export EMAIL="${EMAIL:-$(echo "$secret_json" | jq -r '.email // empty')}"
  
  log "✅ Configuration loaded from AWS Secrets Manager"
}

# ── Configuration ───────────────────────────────────────────────────────────
# Fetch secrets from AWS - script will terminate if this fails
fetch_secrets_from_aws

# Critical configuration from AWS Secrets Manager (no fallbacks)
# Validate that all required variables are non-empty after fetching from Secrets Manager
readonly TF_APP_NAME="${TF_APP_NAME:?TF_APP_NAME not set in secret or is empty}"
readonly S3_BUCKET="${S3_BUCKET:?S3_BUCKET not set in secret or is empty}"
readonly DOMAIN="${DOMAIN:?DOMAIN not set in secret or is empty}"
readonly INTERNAL_DOMAIN="${INTERNAL_DOMAIN:?INTERNAL_DOMAIN not set in secret or is empty}"
readonly EMAIL="${EMAIL:?EMAIL not set in secret or is empty}"

# Optional configuration with defaults
readonly CERT_PREFIX="${CERT_PREFIX:-cert}"
readonly WILDCARD="${WILDCARD:-false}"
readonly RENEWAL_THRESHOLD_DAYS="${RENEWAL_THRESHOLD_DAYS:-30}"

# Construct AWS role name dynamically based on app name
readonly AWS_ROLE_NAME="${TF_APP_NAME}-public-instance-role"

readonly RENEWAL_IMAGE="${DOCKER_IMAGE_NAME:-certificate-renewal}:${DOCKER_IMAGE_TAG:-latest}"
readonly CONSUMER_SERVICE="${CONSUMER_SERVICE:-envoy}"

readonly PUBLIC_CERT_SECRET_TARGET="${PUBLIC_CERT_SECRET_TARGET:-cert.pem}"
readonly PUBLIC_KEY_SECRET_TARGET="${PUBLIC_KEY_SECRET_TARGET:-cert.key}"
readonly INTERNAL_CERT_SECRET_TARGET="${INTERNAL_CERT_SECRET_TARGET:-internal-cert.pem}"
readonly INTERNAL_KEY_SECRET_TARGET="${INTERNAL_KEY_SECRET_TARGET:-internal-key.pem}"
readonly INTERNAL_PFX_SECRET_TARGET="${INTERNAL_PFX_SECRET_TARGET:-internal-cert.pfx}"

readonly WORKER_CONSTRAINT="${WORKER_CONSTRAINT:-node.role==worker}"
readonly STAGING_DIR="/tmp/certificate-renewal"

# Log directory for CloudWatch integration
readonly LOG_DIR="${LOG_DIR:-/var/log}"
readonly LOG_FILE="${LOG_FILE:-certificate-renewal.log}"

# ── Derived names & paths ────────────────────────────────────────────────────
RUN_ID="$(date +%Y%m%d%H%M%S)"
SERVICE_NAME="cert-renewal-${RUN_ID}"

declare -A FILES=(
  # local-name                        remote-path-suffix
  [public-cert.pem]   "public/${RUN_ID}/cert.pem"
  [public-key.pem]    "public/${RUN_ID}/key.pem"
  [internal-cert.pem] "internal/${RUN_ID}/cert.pem"
  [internal-key.pem]  "internal/${RUN_ID}/key.pem"
  [internal-cert.pfx] "internal/${RUN_ID}/cert.pfx"
)

mkdir -p "$STAGING_DIR"

# ── Validation ──────────────────────────────────────────────────────────────
for bin in docker aws; do
  command -v "$bin" &>/dev/null || fatal "Required binary not found: $bin"
done

# ── 1. Launch renewal task ──────────────────────────────────────────────────
log "▶️  Launching renewal service $SERVICE_NAME"
docker service create \
  --name "$SERVICE_NAME" \
  --constraint "$WORKER_CONSTRAINT" \
  --restart-condition none \
  --stop-grace-period 5m \
  --mount type=bind,source="$LOG_DIR",target="$LOG_DIR" \
  --env RUN_ID="$RUN_ID" \
  --env S3_BUCKET="$S3_BUCKET" \
  --env CERT_PREFIX="$CERT_PREFIX" \
  --env DOMAIN="$DOMAIN" \
  --env INTERNAL_DOMAIN="$INTERNAL_DOMAIN" \
  --env EMAIL="$EMAIL" \
  --env AWS_ROLE_NAME="${AWS_ROLE_NAME:-}" \
  --env WILDCARD="$WILDCARD" \
  --env RENEWAL_THRESHOLD_DAYS="$RENEWAL_THRESHOLD_DAYS" \
  --env CERT_OUTPUT_DIR="${CERT_OUTPUT_DIR:-/certs}" \
  --env LOG_DIR="$LOG_DIR" \
  --env LOG_FILE="$LOG_FILE" \
  "$RENEWAL_IMAGE" >/dev/null

# ── 2. Wait for completion ──────────────────────────────────────────────────
log "⏳ Waiting for renewal task to finish…"
until docker service ps --filter desired-state=running "$SERVICE_NAME" | grep -qv Running; do
  sleep 3
done

EXIT_CODE="$(docker service ps --no-trunc "$SERVICE_NAME" \
            --filter desired-state=shutdown --format '{{.ExitCode}}')"
(( EXIT_CODE == 0 )) || fatal "Renewal failed (exit $EXIT_CODE)"

# ── 3. Download artefacts ───────────────────────────────────────────────────
log "📥 Downloading certificates from S3"
for fname in "${!FILES[@]}"; do
  remote="s3://${S3_BUCKET}/${CERT_PREFIX}/${FILES[$fname]}"
  aws s3 cp "$remote" "${STAGING_DIR}/${fname}"
done

# ── 4. Create Swarm secrets ─────────────────────────────────────────────────
log "🔐 Creating Swarm secrets"
declare -A SECRETS=(
  [public-cert.pem]="public-cert-${RUN_ID}"
  [public-key.pem]="public-key-${RUN_ID}"
  [internal-cert.pem]="internal-cert-${RUN_ID}"
  [internal-key.pem]="internal-key-${RUN_ID}"
  [internal-cert.pfx]="internal-pfx-${RUN_ID}"
)
for fname in "${!SECRETS[@]}"; do
  docker secret create "${SECRETS[$fname]}" "${STAGING_DIR}/${fname}" >/dev/null
done

# ── 5. Hot-swap secrets in consumer service ─────────────────────────────────
log "♻️  Updating secrets in $CONSUMER_SERVICE"
docker service update \
  --secret-rm "$PUBLIC_CERT_SECRET_TARGET" \
  --secret-rm "$PUBLIC_KEY_SECRET_TARGET" \
  --secret-rm "$INTERNAL_CERT_SECRET_TARGET" \
  --secret-rm "$INTERNAL_KEY_SECRET_TARGET" \
  --secret-rm "$INTERNAL_PFX_SECRET_TARGET" \
  --secret-add source="${SECRETS[public-cert.pem]}",target="$PUBLIC_CERT_SECRET_TARGET" \
  --secret-add source="${SECRETS[public-key.pem]}",target="$PUBLIC_KEY_SECRET_TARGET" \
  --secret-add source="${SECRETS[internal-cert.pem]}",target="$INTERNAL_CERT_SECRET_TARGET" \
  --secret-add source="${SECRETS[internal-key.pem]}",target="$INTERNAL_KEY_SECRET_TARGET" \
  --secret-add source="${SECRETS[internal-cert.pfx]}",target="$INTERNAL_PFX_SECRET_TARGET" \
  "$CONSUMER_SERVICE"

# ── 6. Cleanup ──────────────────────────────────────────────────────────────
log "🧹 Cleaning up"
docker service rm "$SERVICE_NAME" >/dev/null
rm -f "$STAGING_DIR"/*

log "🎉 Certificates updated:"
printf '   • %s → %s\n' \
  "Public"   "${SECRETS[public-cert.pem]}, ${SECRETS[public-key.pem]}" \
  "Internal" "${SECRETS[internal-cert.pem]}, ${SECRETS[internal-key.pem]}, ${SECRETS[internal-cert.pfx]}"
log "   All secrets now available to $CONSUMER_SERVICE"
