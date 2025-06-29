#!/usr/bin/env bash
# renew-certificate.sh v1.2  —  2025-06-27
#
# Automates issuance / renewal of Let's Encrypt certificates and
# stores them in an S3 bucket for other containers to consume.
# Returns exit code 0 for success, 1 for failure.
#-------------------------------------------------------------------------------

set -Eeuo pipefail

############################################
# Globals & configuration
############################################
readonly LOG_FILE="/var/log/certificate-manager.log"
readonly STATUS_FILE="/tmp/certificate-manager.status"

readonly S3_BUCKET="${S3_BUCKET:-certificate-store}"
readonly CERT_PREFIX="${CERT_PREFIX:-certificates}"

readonly DOMAIN="${DOMAIN:-yourdomain.com}"
readonly INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-}"          # optional
readonly EMAIL="${EMAIL:-admin@yourdomain.com}"

# The **role name** attached to this EC2 instance/Task (not the ARN/ID).
readonly AWS_ROLE_NAME="${AWS_ROLE_NAME:-your-app-private-instance-role}"

readonly WILDCARD="${WILDCARD:-true}"
readonly RENEWAL_THRESHOLD_DAYS="${RENEWAL_THRESHOLD_DAYS:-10}"
readonly CERT_OUTPUT_DIR="${CERT_OUTPUT_DIR:-/app/certs}"

# Certbot Docker image
readonly CERTBOT_IMAGE="certbot/dns-route53:latest"

# single source-of-truth for certificate filenames
readonly CERT_FILES=(cert.pem privkey.pem fullchain.pem)

############################################
# Helper utilities
############################################
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2
}

status() {
  local state="$1" msg="$2"
  printf '%s: %s at %s\n' "$state" "$msg" "$(timestamp)" >"$STATUS_FILE"
  log "STATUS ➜ $state – $msg"
}

on_error() {
  local ec=$? line=$1
  status "FAILED" "line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR
trap cleanup_aws_credentials EXIT      # always clear creds on exit

############################################
# Prerequisite check (fail fast)
############################################
for bin in jq aws openssl docker; do
  command -v "$bin" >/dev/null 2>&1 || {
    log "ERROR: required binary '$bin' not found in PATH"; exit 1;
  }
done

############################################
# Docker helpers
############################################
pull_certbot_image() {
  log "Pulling certbot Docker image: $CERTBOT_IMAGE"
  if docker pull "$CERTBOT_IMAGE"; then
    log "Successfully pulled certbot image"
  else
    log "ERROR: Failed to pull certbot image"
    status "FAILED" "Docker image pull failed"
    exit 1
  fi
}

run_certbot() {
  local cert_dir="$1"
  local domain="$2"
  local wildcard="$3"
  
  local docker_args=(
    run --rm
    -v "$cert_dir:/etc/letsencrypt"
    -v "/var/lib/letsencrypt:/var/lib/letsencrypt"
    -v "/var/log/letsencrypt:/var/log/letsencrypt"
    -e AWS_ACCESS_KEY_ID
    -e AWS_SECRET_ACCESS_KEY
    -e AWS_SESSION_TOKEN
    -e AWS_DEFAULT_REGION
    "$CERTBOT_IMAGE"
  )
  
  local certbot_args=(
    certonly --dns-route53
    -m "$EMAIL" --agree-tos --non-interactive
  )
  
  if [[ $wildcard == true ]]; then
    certbot_args+=(-d "*.${domain}" -d "${domain}")
  else
    certbot_args+=(-d "${domain}")
  fi
  
  log "Running certbot for domain: $domain"
  docker "${docker_args[@]}" certbot "${certbot_args[@]}"
}

############################################
# AWS helpers
############################################
fetch_aws_credentials() {
  log "Fetching AWS credentials using IMDSv2"

  local token
  token=$(curl -s -X PUT \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 300" \
      "http://169.254.169.254/latest/api/token") || true

  [[ -z $token ]] && { log "ERROR: IMDSv2 token unavailable"; status "FAILED" "IMDSv2 token missing"; exit 1; }

  local creds_json
  creds_json=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
      "http://169.254.169.254/latest/meta-data/iam/security-credentials/$AWS_ROLE_NAME") || true

  if [[ $(jq -r '.Code' <<<"$creds_json") != "Success" ]]; then
    log "ERROR: failed to fetch AWS credentials (role: $AWS_ROLE_NAME)"
    status "FAILED" "AWS credential fetch failed"
    exit 1
  fi

  export AWS_ACCESS_KEY_ID=$(jq -r '.AccessKeyId'     <<<"$creds_json")
  export AWS_SECRET_ACCESS_KEY=$(jq -r '.SecretAccessKey' <<<"$creds_json")
  export AWS_SESSION_TOKEN=$(jq -r '.Token'           <<<"$creds_json")
  export AWS_DEFAULT_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/placement/region)

  log "AWS credentials exported to environment (region: $AWS_DEFAULT_REGION)"
}

cleanup_aws_credentials() {
  log "Cleaning up AWS credentials from environment"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION
}

############################################
# S3 Certificate Store
############################################
download_certificate_from_s3() {
  local cert_type="$1"   # external | internal
  local local_dir="$2"

  log "Downloading $cert_type certificate from S3"

  local s3_path="$CERT_PREFIX/$cert_type"

  for file in "${CERT_FILES[@]}"; do
    local s3_key="$s3_path/$file"
    local local_file="$local_dir/${cert_type}-$file"
    if aws s3 cp --only-show-errors "s3://$S3_BUCKET/$s3_key" "$local_file"; then
      log "Downloaded $file"
    else
      log "Certificate file $file not found in S3"
      return 1
    fi
  done
  log "$cert_type certificate downloaded successfully"
}

upload_certificate_to_s3() {
  local cert_type="$1"   # external | internal
  local local_dir="$2"

  log "Uploading $cert_type certificate to S3"

  local s3_path="$CERT_PREFIX/$cert_type"

  for file in "${CERT_FILES[@]}"; do
    local s3_key="$s3_path/$file"
    local local_file="$local_dir/${cert_type}-$file"
    aws s3 cp --only-show-errors "$local_file" "s3://$S3_BUCKET/$s3_key"
    log "Uploaded $file"
  done
}

############################################
# Certificate validation
############################################
check_certificate_validity() {
  local cert_file="$1" days_threshold="${2:-$RENEWAL_THRESHOLD_DAYS}"

  log "Checking certificate: $cert_file (threshold $days_threshold d)"

  [[ -f $cert_file ]] || { log "Missing file $cert_file"; return 1; }

  local expiry_date expiry_ts now days_left
  expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2) || return 1
  expiry_ts=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s)
  now=$(date +%s)
  days_left=$(( (expiry_ts - now) / 86400 ))

  log "Expires: $expiry_date  (in $days_left days)"

  (( days_left > days_threshold ))
}

############################################
# Certificate output management
############################################
prepare_certificates_for_output() {
  local cert_dir="$1"

  log "Preparing certificates for output → $CERT_OUTPUT_DIR"
  install -m 700 -d "$CERT_OUTPUT_DIR"

  # external certs
  cp "$cert_dir"/external-cert.pem     "$CERT_OUTPUT_DIR/cert.pem"
  cp "$cert_dir"/external-privkey.pem  "$CERT_OUTPUT_DIR/cert.key"
  cp "$cert_dir"/external-fullchain.pem "$CERT_OUTPUT_DIR/fullchain.pem"

  # .pfx for .NET
  openssl pkcs12 -export               \
      -in  "$CERT_OUTPUT_DIR/cert.pem" \
      -inkey "$CERT_OUTPUT_DIR/cert.key" \
      -out "$CERT_OUTPUT_DIR/aspnetapp.pfx" \
      -passout pass:

  # internal (optional)
  if [[ -n "$INTERNAL_DOMAIN" && -f "$cert_dir/internal-cert.pem" ]]; then
    cp "$cert_dir"/internal-*.pem "$CERT_OUTPUT_DIR"/
  fi

  chmod 400 "$CERT_OUTPUT_DIR"/*.{pem,pfx}

  date -u +%Y-%m-%dT%H:%M:%SZ > "$CERT_OUTPUT_DIR/last-updated.txt"
  log "Certificates prepared successfully"
}

############################################
# Certificate renewal
############################################
renew_certificates() {
  local cert_dir="$1"
  
  log "Renewing certificates with certbot"

  # Ensure certbot directories exist
  mkdir -p "$cert_dir"/{live,renewal} /var/{lib,log}/letsencrypt

  # Pull the certbot image
  pull_certbot_image

  # -------- external --------
  log "Renewing external cert for $DOMAIN"
  run_certbot "$cert_dir" "$DOMAIN" "$WILDCARD"

  local external_dir="$cert_dir/live/$DOMAIN"
  cp "$external_dir"/privkey.pem   "$cert_dir/external-privkey.pem"
  cp "$external_dir"/cert.pem      "$cert_dir/external-cert.pem"
  cp "$external_dir"/fullchain.pem "$cert_dir/external-fullchain.pem"

  # -------- internal (optional) --------
  if [[ -n "$INTERNAL_DOMAIN" ]]; then
    log "Renewing internal cert for $INTERNAL_DOMAIN"
    run_certbot "$cert_dir" "$INTERNAL_DOMAIN" true

    local internal_dir="$cert_dir/live/$INTERNAL_DOMAIN"
    cp "$internal_dir"/privkey.pem   "$cert_dir/internal-privkey.pem"
    cp "$internal_dir"/cert.pem      "$cert_dir/internal-cert.pem"
    cp "$internal_dir"/fullchain.pem "$cert_dir/internal-fullchain.pem"
  fi

  chmod 400 "$cert_dir"/*.pem
  log "Certificates renewed successfully"
}

############################################
# Main logic
############################################
main() {
  log "Certificate renewal started (threshold: $RENEWAL_THRESHOLD_DAYS d)"
  status "IN_PROGRESS" "Certificate renewal started"

  # workspace & cleanup
  local cert_dir
  cert_dir=$(mktemp -d /tmp/certificates.XXXXXX)
  trap 'rm -rf "$cert_dir"' EXIT

  fetch_aws_credentials

  # ---- download existing certs ----
  local have_external=false have_internal=false renewal_needed=false

  if download_certificate_from_s3 external "$cert_dir"; then
    have_external=true
  fi
  if [[ -n $INTERNAL_DOMAIN ]] && download_certificate_from_s3 internal "$cert_dir"; then
    have_internal=true
  fi

  # ---- validity checks ----
  if $have_external && check_certificate_validity "$cert_dir/external-cert.pem"; then
    log "External cert still valid"
  else
    renewal_needed=true
  fi

  if [[ -n $INTERNAL_DOMAIN ]]; then
    if $have_internal && check_certificate_validity "$cert_dir/internal-cert.pem"; then
      log "Internal cert still valid"
    else
      renewal_needed=true
    fi
  fi

  # ---- renew if necessary ----
  if $renewal_needed; then
    log "Renewal required → invoking certbot"
    renew_certificates "$cert_dir"
    
    upload_certificate_to_s3 external "$cert_dir"
    [[ -n $INTERNAL_DOMAIN ]] && upload_certificate_to_s3 internal "$cert_dir"
  else
    log "All certificates healthy; skipping renewal"
  fi

  prepare_certificates_for_output "$cert_dir"

  log "Certificate renewal completed successfully 🎉"
  status "SUCCESS" "Certificate renewal completed"
  exit 0
}

main "$@" 