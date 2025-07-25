#!/usr/bin/env bash
###############################################################################
# trigger-certificate-renewal.sh — one-shot cert rotation for Docker Swarm
#
# 1. Launch a transient Swarm service that calls renew-certificate.sh
# 2. Download the artefacts from S3 and load / rotate them as Swarm secrets
# 3. Clean up everything on exit
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit

###############################################################################
# Parse command line arguments
###############################################################################
RENEWAL_ARGS=()
HELP_REQUESTED=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      RENEWAL_ARGS+=("--force")
      shift
      ;;
    --dry-run)
      RENEWAL_ARGS+=("--dry-run")
      shift
      ;;
    --staging)
      RENEWAL_ARGS+=("--staging")
      shift
      ;;
    --help|-h)
      HELP_REQUESTED=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      HELP_REQUESTED=true
      shift
      ;;
  esac
done

if [[ $HELP_REQUESTED == true ]]; then
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --force     Renew even if certificates are still valid.
  --dry-run   Skip certbot, S3 and Secrets Manager writes.
  --staging   Use Let's Encrypt staging environment.
  --help, -h  Show this help message.

Environment Variables:
  AWS_SECRET_NAME              - Required: AWS Secrets Manager secret name
  TIMEOUT_SECONDS             - Optional: Service timeout (default: 300)
  WORKER_CONSTRAINT           - Optional: Swarm constraint (default: node.role==worker)
  RENEWAL_THRESHOLD_DAYS      - Optional: Days before renewal (default: 10)

EOF
  exit 0
fi

# Log the arguments being passed
if [[ ${#RENEWAL_ARGS[@]} -gt 0 ]]; then
  log "Certificate renewal arguments: ${RENEWAL_ARGS[*]}"
fi

###############################################################################
# Constants / defaults
###############################################################################
readonly RUN_ID=$(date +%Y%m%d%H%M%S)
readonly SERVICE_NAME="cert-renew-${RUN_ID}"
readonly STAGING_DIR=$(mktemp -d -p /var/lib/certificate-manager cert-renew.XXXXXXXX)
readonly LETSENCRYPT_DIR=${LETSENCRYPT_DIR:-/etc/letsencrypt}
readonly LETSENCRYPT_LOG_DIR=${LETSENCRYPT_LOG_DIR:-/var/log/letsencrypt}
readonly WORKER_LOG_DIR=${WORKER_LOG_DIR:-/var/log/certificate-manager}
readonly TIMEOUT=${TIMEOUT_SECONDS:-300}                # 5 min
readonly WORKER_CONSTRAINT=${WORKER_CONSTRAINT:-node.role==worker}
readonly RENEWAL_THRESHOLD_DAYS=${RENEWAL_THRESHOLD_DAYS:-10}

# Swarm-secret names created at runtime and removed on exit
TEMP_SECRET_IDS=()

# Associative array to store new secret names for domain certificates
declare -A NEW_SECRETS

###############################################################################
# Logging helpers
###############################################################################
_ts()   { date '+%F %T'; }
log()   { printf '[ %s ] TRIGGER %s\n' "$(_ts)" "$*" >&2; }
fatal()   { log "ERROR: $*"; exit 1; }

###############################################################################
# Cleanup ─ always
###############################################################################
cleanup() {
  local rc=$?
  log "clean-up (exit code: $rc)…"
  docker service rm "$SERVICE_NAME" &>/dev/null || true
  # Only clean up temporary secrets, not certificate secrets
  ((${#TEMP_SECRET_IDS[@]})) && docker secret rm "${TEMP_SECRET_IDS[@]}" &>/dev/null || true
  # rm -rf "$STAGING_DIR"
}
trap cleanup EXIT
trap 'fatal "command failed on line $LINENO"' ERR

###############################################################################
# Dependency check
###############################################################################
for cmd in docker aws jq; do command -v "$cmd" &>/dev/null || fatal "$cmd missing"; done

###############################################################################
# Swarm must be initialised
###############################################################################
# TODO: Remove this once we switch to minimal AMI
wait_for_docker() {
  local max_attempts=30
  local wait_seconds=10
  local attempt=1

  log "Waiting for Docker service to be ready …"

  while (( attempt <= max_attempts )); do
    if docker info &>/dev/null; then
      log "Docker service is ready ✅"
      return 0
    fi

    log "Docker not ready yet (attempt $attempt/$max_attempts) – waiting ${wait_seconds}s"
    sleep "$wait_seconds"
    ((attempt++))
  done

  log "ERROR: Docker service failed to become ready after $((max_attempts * wait_seconds)) seconds"
  status "FAILED" "Docker service timeout"
  exit 1
}

wait_for_swarm() {
  local max_attempts=30
  local wait_seconds=5
  local attempt=1

  log "Waiting for Docker Swarm to be ready …"

  while (( attempt <= max_attempts )); do 
    if docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null \
          | grep -Eq '^(active|pending)$'; then
      log "Docker Swarm is ready ✅"
      return 0
    fi

    log "Docker Swarm not ready yet (attempt $attempt/$max_attempts) – waiting ${wait_seconds}s"
    sleep "$wait_seconds"
    ((attempt++))
  done

  log "ERROR: Docker Swarm failed to become ready after $((max_attempts * wait_seconds)) seconds"
  status "FAILED" "Docker Swarm timeout"
  exit 1
}

wait_for_docker
wait_for_swarm

###############################################################################
# Pull runtime configuration from AWS Secrets Manager
###############################################################################
[[ -n ${AWS_SECRET_NAME:-} ]] || fatal "AWS_SECRET_NAME env var is required"

secret=$(aws secretsmanager get-secret-value \
           --secret-id "$AWS_SECRET_NAME" \
           --query SecretString --output text) || fatal "cannot fetch secret"

json() { jq -r "$1" <<<"$secret"; }

APP_NAME=${APP_NAME:-$(json .Infrastructure_APP_NAME)}
AWS_REGION=${AWS_REGION:-$(json .Infrastructure_AWS_REGION)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
ACME_EMAIL=${ACME_EMAIL:-$(json .Infrastructure_ACME_EMAIL)}
CERTIFICATE_STORE=${CERTIFICATE_STORE:-$(json .Infrastructure_CERTIFICATE_STORE)}
DOMAIN_NAME=${DOMAIN_NAME:-$(json .Infrastructure_DOMAIN_NAME)}
SUBDOMAINS=${SUBDOMAINS:-$(json .Infrastructure_SUBDOMAIN_NAMES)}
AWS_ROLE_NAME=${AWS_ROLE_NAME:-${APP_NAME}-ec2-public-instance-role}


: "${APP_NAME:?} ${CERTIFICATE_STORE:?} ${ACME_EMAIL:?} ${SUBDOMAINS:?} ${DOMAIN_NAME:?}"

# Split SUBDOMAINS into array and construct full domain names
IFS=',' read -r -a SUBDOMAIN_ARRAY <<<"$SUBDOMAINS"
DOMAINS=()
for s in "${SUBDOMAIN_ARRAY[@]}"; do
  DOMAINS+=("${s}.${DOMAIN_NAME}")
done

# Also update SUBDOMAIN_NAMES to be consistent
SUBDOMAIN_NAMES=$(IFS=,; printf "%s," "${DOMAINS[@]}" | sed 's/,$//')

RENEW_IMAGE=${RENEWAL_IMAGE:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}/certbot:latest}

###############################################################################
# Define service mappings for certificate rotation
###############################################################################
# Simple static mapping of domains to services for certificate updates
SERVICES_BY_DOMAIN=$(jq -n \
  --arg api_domain "api.${DOMAIN_NAME}" \
  --arg internal_domain "internal.${DOMAIN_NAME}" \
  '{($api_domain): ["envoy_app"], ($internal_domain): ["authentication_app"]}')
log "Configured service mappings: $SERVICES_BY_DOMAIN"

###############################################################################
# Swarm secret helper
###############################################################################
make_secret() {
  local name=$1 val=$2
  id=$(printf '%s' "$val" | docker secret create "$name" -) \
      || fatal "secret $name create failed"
  TEMP_SECRET_IDS+=("$name")
  echo "$name"
}

aws_role_sec=$(make_secret aws_role_${RUN_ID}     "$AWS_ROLE_NAME")
cert_store_sec=$(make_secret cert_store_${RUN_ID} "$CERTIFICATE_STORE")
acme_sec=$(make_secret acme_email_${RUN_ID}       "$ACME_EMAIL")
domains_sec=$(make_secret domains_${RUN_ID}       "$SUBDOMAIN_NAMES")

###############################################################################
# Check for missing secrets to determine if force upload is needed
###############################################################################
FORCE_UPLOAD=false
for d in "${DOMAINS[@]}"; do
  slug=${d//./-}
  # Check certificate files
  for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
    docker secret inspect "${slug}-${f}" &>/dev/null || { FORCE_UPLOAD=true; break 2; }
  done
done

###############################################################################
# Run the renewal task
###############################################################################
log "launching renewal service $SERVICE_NAME"
log "using image: $RENEW_IMAGE"
if [[ ${#RENEWAL_ARGS[@]} -gt 0 ]]; then
  log "with arguments: ${RENEWAL_ARGS[*]}"
fi
log "See service logs at cert-renew-${RUN_ID}"

service_id=$(docker service create --detach --quiet --with-registry-auth \
  --name "$SERVICE_NAME" \
  --constraint "$WORKER_CONSTRAINT" \
  --restart-condition none \
  --stop-grace-period 5m \
  --mount "type=bind,source=$WORKER_LOG_DIR,target=$WORKER_LOG_DIR" \
  --mount "type=bind,source=$LETSENCRYPT_DIR,target=$LETSENCRYPT_DIR" \
  --mount "type=bind,source=$LETSENCRYPT_LOG_DIR,target=$LETSENCRYPT_LOG_DIR" \
  --env RUN_ID="$RUN_ID" \
  --env CERT_PREFIX="$APP_NAME" \
  --env RENEWAL_THRESHOLD_DAYS="$RENEWAL_THRESHOLD_DAYS" \
  --secret "source=$aws_role_sec,target=AWS_ROLE_NAME" \
  --secret "source=$cert_store_sec,target=CERTIFICATE_STORE" \
  --secret "source=$acme_sec,target=ACME_EMAIL" \
  --secret "source=$domains_sec,target=DOMAINS_NAMES" \
  --env AWS_SECRET_NAME="$AWS_SECRET_NAME" \
  --env FORCE_UPLOAD="$FORCE_UPLOAD" \
  --log-driver awslogs \
  --log-opt awslogs-group="/aws/ec2/$APP_NAME-certificate-manager" \
  --log-opt awslogs-stream="$SERVICE_NAME" \
  --log-opt awslogs-region="$AWS_REGION" \
  "$RENEW_IMAGE" \
  ${RENEWAL_ARGS[@]+"${RENEWAL_ARGS[@]}"}) || fatal "service create failed"

###############################################################################
# Wait for completion (timeout $TIMEOUT s)
###############################################################################
log "Waiting for renewal task to complete…"
end=$((SECONDS+TIMEOUT))
while (( SECONDS < end )); do
  state=$(docker service ps --filter desired-state=shutdown \
          --format '{{.CurrentState}}' "$service_id" | head -n1)
  case $state in
    *Complete*) log "service completed OK"; break ;;
    *Failed*)  fatal "renewal task failed" ;;
    *)         state=running; log "current state: $state" ;;
  esac
  sleep 3
done
(( SECONDS < end )) || fatal "renewal task timed out"

###############################################################################
# Pull renewal status
###############################################################################
status_json="$STAGING_DIR/status.json"
s3_status_path="s3://$CERTIFICATE_STORE/$APP_NAME/$RUN_ID/renewal-status.json"

log "checking for renewal status at: $s3_status_path"

# Check if the file exists first
if aws s3 ls "$s3_status_path" &>/dev/null; then
  log "renewal-status.json found, downloading..."
  aws s3 cp "$s3_status_path" "$status_json" \
            || fatal "failed to download renewal-status.json"
  log "renewal-status.json downloaded successfully at $status_json"
else
  log "no renewal-status.json found at: $s3_status_path"
  exit 0
fi

# Read renewal status from JSON
if ! status_data=$(jq -e . "$status_json"); then
  log "invalid JSON in renewal-status.json"
  exit 1
fi

log "renewal status: $status_data"

# Get renewal status with error handling
if ! renewed=$(jq -r '.renewal_occurred' "$status_json" 2>&1); then
  log "ERROR: Failed to extract renewal_occurred from JSON: $renewed"
  exit 1
fi

# Get renewed domains with error handling
if ! renew_domains_output=$(jq -r '.renewed_domains[]' "$status_json" 2>&1); then
  log "ERROR: Failed to extract renewed_domains from JSON: $renew_domains_output"
  exit 1
fi

# Convert to array
renew_domains=()
while IFS= read -r domain; do
  [[ -n "$domain" ]] && renew_domains+=("$domain")
done <<< "$renew_domains_output"

log "Extracted renewed domains: ${renew_domains[*]}"

if [[ $renewed == true && ${#renew_domains[@]} -gt 0 ]]; then
  log "renewal occurred with ${#renew_domains[@]} domains - continuing"
elif [[ $FORCE_UPLOAD == true ]]; then
  log "force upload enabled - continuing despite no renewal"
else
  log "no domains renewed and force upload disabled - exit"
  exit 0
fi

###############################################################################
# Fetch artefacts & create Swarm secrets
###############################################################################
log "downloading cert artefacts…"

for d in "${renew_domains[@]}"; do
  dest="$STAGING_DIR/$d"; mkdir -p "$dest"
  s3_cert_path="s3://$CERTIFICATE_STORE/$APP_NAME/$RUN_ID/$d/"
  log "downloading certificates for domain: $d from $s3_cert_path"
  
  aws s3 cp "$s3_cert_path" "$dest/" --recursive \
            || fatal "download failed: $d"
  
  log "downloaded certificates for $d, creating Swarm secrets..."
  # Handle certificate files (excluding password)
  for f in cert.pem privkey.pem fullchain.pem cert.pfx; do
    [[ -f $dest/$f ]] || continue
    sec="${d//./-}-$f-$RUN_ID"
    docker secret create "$sec" "$dest/$f" &>/dev/null \
      || fatal "secret create failed: $sec"
    NEW_SECRETS["$d/$f"]=$sec
    log "created secret: $sec"
  done
  
done
log "artefacts ready as Swarm secrets"

###############################################################################
# (Optional) hot-swap secrets in target services
###############################################################################
if [[ -n ${SERVICES_BY_DOMAIN:-} && $SERVICES_BY_DOMAIN != "{}" ]]; then
  log "rotating secrets in services…"
  for d in "${renew_domains[@]}"; do
    mapfile -t svcs < <(jq -r --arg d "$d" '.[$d][]?' <<<"$SERVICES_BY_DOMAIN")
    (( ${#svcs[@]} )) || continue
    for svc in "${svcs[@]}"; do
      # Check if service exists before attempting to update
      if ! docker service inspect "$svc" &>/dev/null; then
        log " ⚠ service $svc does not exist, skipping"
        continue
      fi
      
      docker service update --quiet \
        --secret-rm cert.pem --secret-rm privkey.pem \
        --secret-rm fullchain.pem --secret-rm cert.pfx \
        --secret-add source="${NEW_SECRETS[$d/cert.pem]}",target=cert.pem \
        --secret-add source="${NEW_SECRETS[$d/privkey.pem]}",target=privkey.pem \
        --secret-add source="${NEW_SECRETS[$d/fullchain.pem]}",target=fullchain.pem \
        --secret-add source="${NEW_SECRETS[$d/cert.pfx]}",target=cert.pfx \
        "$svc" || fatal "cannot update $svc"
      log " ↻ $svc updated"
    done
  done
fi

###############################################################################
# Done
###############################################################################
log "✅ certificate rotation complete (domains: ${renew_domains[*]})"
