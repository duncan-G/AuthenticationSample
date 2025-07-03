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
fatal()    { log "\e[31mERROR:\e[0m $*"; exit 1; }

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
DOMAIN_NAME="${DOMAIN_NAME:-$(jq -r '.DOMAIN_NAME' <<<"$secret_json")}"
# Extract subdomain names from SUBDOMAIN_NAME_1, SUBDOMAIN_NAME_2, etc.
SUBDOMAIN_NAMES="$(jq -r 'to_entries | map(select(.key | startswith("SUBDOMAIN_NAME_"))) | sort_by(.key) | .[].value' <<<"$secret_json" | tr '\n' ',')"
EMAIL="${EMAIL:-$(jq -r '.EMAIL' <<<"$secret_json")}"

for v in APP_NAME CERTIFICATE_STORE DOMAIN_NAME EMAIL; do
  [[ -z "${!v}" || ${!v} == "null" ]] && fatal "\"$v\" missing in secret or env"
  readonly "$v"
done

readonly SUBDOMAIN_NAMES

RENEWAL_THRESHOLD_DAYS="${RENEWAL_THRESHOLD_DAYS:-10}"
AWS_ROLE_NAME="${AWS_ROLE_NAME:-${APP_NAME}-public-instance-role}"
RENEWAL_IMAGE="${RENEWAL_IMAGE:-${APP_NAME}/certbot:latest}"

# Services to update with public certificates (comma-separated)
PUBLIC_SERVICES_STR="${PUBLIC_SERVICES:-}"
# Convert to array
IFS=',' read -ra PUBLIC_SERVICES <<< "$PUBLIC_SERVICES_STR"

# Services to update with internal certificates (comma-separated)
INTERNAL_SERVICES_STR="${INTERNAL_SERVICES:-}"
# Convert to array
IFS=',' read -ra INTERNAL_SERVICES <<< "$INTERNAL_SERVICES_STR"

readonly CERT_OUTPUT_DIR="${CERT_OUTPUT_DIR:-/certs}"
readonly PUBLIC_CERT_SECRET_TARGET="${PUBLIC_CERT_SECRET_TARGET:-cert.pem}"
readonly PUBLIC_KEY_SECRET_TARGET="${PUBLIC_KEY_SECRET_TARGET:-cert.key}"
readonly INTERNAL_CERT_SECRET_TARGET="${INTERNAL_CERT_SECRET_TARGET:-internal-cert.pem}"
readonly INTERNAL_KEY_SECRET_TARGET="${INTERNAL_KEY_SECRET_TARGET:-internal-key.pem}"
readonly INTERNAL_PFX_SECRET_TARGET="${INTERNAL_PFX_SECRET_TARGET:-internal-cert.pfx}"

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

create_secret aws_role_name_${RUN_ID}   "$AWS_ROLE_NAME"
create_secret certificate_store_${RUN_ID}       "$CERTIFICATE_STORE"
create_secret acme_email_${RUN_ID}      "$EMAIL"
create_secret domain_name_${RUN_ID}     "$DOMAIN_NAME"
create_secret subdomain_names_${RUN_ID} "$SUBDOMAIN_NAMES"
log "✅ Runtime secrets ready"

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
  --secret source=domains${RUN_ID},target=SUBDOMAIN_NAMES \
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

###############################################################################
# Download artefacts from S3
###############################################################################
log "📥 Downloading certificates to $STAGING_DIR"

declare -A FILEMAP=(
  [public-cert.pem]   "public/${RUN_ID}/cert.pem"
  [public-key.pem]    "public/${RUN_ID}/key.pem"
  [internal-cert.pem] "internal/${RUN_ID}/cert.pem"
  [internal-key.pem]  "internal/${RUN_ID}/key.pem"
  [internal-cert.pfx] "internal/${RUN_ID}/cert.pfx"
)

for f in "${!FILEMAP[@]}"; do
  aws s3 cp "s3://${CERTIFICATE_STORE}/${APP_NAME}/${FILEMAP[$f]}" "${STAGING_DIR}/$f" --quiet || \
    fatal "Missing artefact: ${FILEMAP[$f]}"
done

###############################################################################
# Create Swarm secrets for the new certificates
###############################################################################
log "🔐 Generating Swarm secrets for fresh certs"
declare -A NEW_SECRETS=(
  [public-cert.pem]   "public-cert-${RUN_ID}"
  [public-key.pem]    "public-key-${RUN_ID}"
  [internal-cert.pem] "internal-cert-${RUN_ID}"
  [internal-key.pem]  "internal-key-${RUN_ID}"
  [internal-cert.pfx] "internal-pfx-${RUN_ID}"
)

for f in "${!NEW_SECRETS[@]}"; do
  docker secret create "${NEW_SECRETS[$f]}" "${STAGING_DIR}/$f" >/dev/null || \
    fatal "Unable to create secret for $f"
  SECRETS_TO_CLEANUP+=("${NEW_SECRETS[$f]}")
done

###############################################################################
# Hot‑swap secrets into the consumer services
###############################################################################

# Update services with public certificates
if [ ${#PUBLIC_SERVICES[@]} -gt 0 ]; then
  log "🌐 Updating ${#PUBLIC_SERVICES[@]} service(s) with public certificates"
  for service in "${PUBLIC_SERVICES[@]}"; do
    log "♻️  Updating public certificates in $service"
    
    docker service update \
      --secret-rm "$PUBLIC_CERT_SECRET_TARGET" \
      --secret-rm "$PUBLIC_KEY_SECRET_TARGET" \
      --secret-add source="${NEW_SECRETS[public-cert.pem]}",target="$PUBLIC_CERT_SECRET_TARGET" \
      --secret-add source="${NEW_SECRETS[public-key.pem]}",target="$PUBLIC_KEY_SECRET_TARGET" \
      "$service" || fatal "Failed to update public certificates in service: $service"
  done
else
  log "ℹ️  No services configured for public certificate updates"
fi

# Update services with internal certificates
if [ ${#INTERNAL_SERVICES[@]} -gt 0 ]; then
  log "🔒 Updating ${#INTERNAL_SERVICES[@]} service(s) with internal certificates"
  for service in "${INTERNAL_SERVICES[@]}"; do
    log "♻️  Updating internal certificates in $service"
    
    docker service update \
      --secret-rm "$INTERNAL_CERT_SECRET_TARGET" \
      --secret-rm "$INTERNAL_KEY_SECRET_TARGET" \
      --secret-rm "$INTERNAL_PFX_SECRET_TARGET" \
      --secret-add source="${NEW_SECRETS[internal-cert.pem]}",target="$INTERNAL_CERT_SECRET_TARGET" \
      --secret-add source="${NEW_SECRETS[internal-key.pem]}",target="$INTERNAL_KEY_SECRET_TARGET" \
      --secret-add source="${NEW_SECRETS[internal-cert.pfx]}",target="$INTERNAL_PFX_SECRET_TARGET" \
      "$service" || fatal "Failed to update internal certificates in service: $service"
  done
else
  log "ℹ️  No services configured for internal certificate updates"
fi

###############################################################################
log "🎉 Certificates rotated successfully"
if [ ${#PUBLIC_SERVICES[@]} -gt 0 ]; then
  log "   Public certificates updated in: ${PUBLIC_SERVICES[*]}"
fi
if [ ${#INTERNAL_SERVICES[@]} -gt 0 ]; then
  log "   Internal certificates updated in: ${INTERNAL_SERVICES[*]}"
fi
