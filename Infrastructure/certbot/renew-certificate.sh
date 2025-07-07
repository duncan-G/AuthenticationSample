#!/usr/bin/env bash
###############################################################################
# renew-certificate.sh  ▸ 2025-07-03
#
# ACME automation for multi‑domain stacks running in AWS (Route 53).
# Optimised for Docker **Swarm** but works standalone.
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies
#   3 - AWS credential error
#   4 - Certbot error
#   5 - S3 upload error
###############################################################################
set -Eeuo pipefail
shopt -s inherit_errexit nullglob

################################################################################
# Globals ---------------------------------------------------------------------
################################################################################
readonly SCRIPT_NAME=${0##*/}
readonly DEFAULT_RENEWAL_THRESHOLD_DAYS=10
readonly LETSENCRYPT_DIR=/etc/letsencrypt

# Exit code tracking
EXIT_CODE=0

################################################################################
# Logging setup ---------------------------------------------------------------
################################################################################
LOG_DIR="/var/log/certificate-manager"
LOG_FILE="${LOG_DIR}/certificate-renewal.log"
STATUS_FILE="${LOG_DIR}/certificate-renewal.status"

mkdir -p "$LOG_DIR"

_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
status() {
  printf '%s: %s at %s\n' "$1" "$2" "$(_ts)" >"$STATUS_FILE"
  log "STATUS ➜ $1 – $2"
}

log "🚀 Starting certificate renewal script: $SCRIPT_NAME"

################################################################################
# Usage -----------------------------------------------------------------------
################################################################################
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--force] [--dry-run] [--staging]

Options:
  --force        Renew certificates regardless of remaining validity.
  --dry-run      Execute everything except the final Certbot/S3/AWS writes.
  --staging      Use Let's Encrypt staging environment (implies --test-cert).
  -h, --help     Show this help.
EOF
}

################################################################################
# CLI arguments ----------------------------------------------------------------
################################################################################
log "🔧 Parsing command line arguments..."
FORCE=false
DRY_RUN=false
STAGING=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=true ; log "  ➜ Force renewal enabled" ; shift ;;
    --dry-run) DRY_RUN=true ; log "  ➜ Dry run mode enabled" ; shift ;;
    --staging) STAGING=true ; log "  ➜ Staging environment enabled" ; shift ;;
    -h|--help) usage ; exit 0 ;;
    *) echo "Unknown option: $1" >&2 ; usage ; exit 1 ;;
  esac
done

log "  ➜ Force mode: $FORCE"
log "  ➜ Dry run mode: $DRY_RUN"
log "  ➜ Staging mode: $STAGING"

################################################################################
# Helper: import a Swarm secret if env‑var is empty ----------------------------
################################################################################
import_secret() {
    local var=$1
    local path="/run/secrets/$1"

    if [[ -z ${!var-} && -f $path ]]; then
      export "$var"="$(<"$path")"
      log "  ➜ Imported secret: $var (from $path)"
    fi
}

# Mandatory/optional secrets
log "🔐 Loading secrets..."
for s in AWS_ROLE_NAME CERTIFICATE_STORE ACME_EMAIL DOMAINS_NAMES; do
  import_secret "$s"
done

################################################################################
# Verify mandatory dependencies & variables -----------------------------------
################################################################################
log "🔍 Checking required dependencies..."
need_cmd() { 
  if command -v "$1" &>/dev/null; then
    log "  ✅ Found: $1"
    return 0
  else
    log "  ❌ Missing: $1"
    echo "ERROR: '$1' not found in PATH" >&2 
    EXIT_CODE=2
    return 1
  fi
}

for bin in jq aws openssl certbot curl; do 
  need_cmd "$bin" || exit $EXIT_CODE
done

log "📋 Validating required environment variables..."
[[ -n ${CERTIFICATE_STORE:-}       ]] || { log "  ❌ Missing: CERTIFICATE_STORE" ; echo "CERTIFICATE_STORE is required (secret or env)" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${ACME_EMAIL:-}           ]] || { log "  ❌ Missing: ACME_EMAIL" ; echo "ACME_EMAIL is required" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${AWS_ROLE_NAME:-}   ]] || { log "  ❌ Missing: AWS_ROLE_NAME" ; echo "AWS_ROLE_NAME is required" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${DOMAINS_NAMES:-}         ]] || { log "  ❌ Missing: DOMAINS_NAMES" ; echo "DOMAINS_NAMES is required (comma‑separated)" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${AWS_SECRET_NAME:-} ]] || { log "  ❌ Missing: AWS_SECRET_NAME" ; echo "AWS_SECRET_NAME is required (environment variable)" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }

log "  ✅ All required environment variables present"

log "⚙️  Setting up configuration variables..."
RENEWAL_THRESHOLD_DAYS=${RENEWAL_THRESHOLD_DAYS:-$DEFAULT_RENEWAL_THRESHOLD_DAYS}
CERT_PREFIX=${CERT_PREFIX:-certificates}
RUN_ID=${RUN_ID:-$(date +%Y%m%d%H%M%S)}
CERT_OUTPUT_DIR="/app/certs"

log "  ➜ Renewal threshold: ${RENEWAL_THRESHOLD_DAYS} days"
log "  ➜ Certificate prefix: $CERT_PREFIX"
log "  ➜ Run ID: $RUN_ID"
log "  ➜ Certificate output directory: $CERT_OUTPUT_DIR"

IFS=',' read -r -a DOMAIN_ARRAY <<< "$DOMAINS_NAMES"
log "  ➜ Domains to process: ${#DOMAIN_ARRAY[@]} (${DOMAIN_ARRAY[*]})"

log "📁 Creating required directories..."
mkdir -p "$LOG_DIR" /var/{lib,log}/letsencrypt "$CERT_OUTPUT_DIR"
log "  ✅ Directories created successfully"

log "🎯 Initialization complete - proceeding to main execution"

# Set up error handling
trap 'status FAILED "line $LINENO exited with code $?"; EXIT_CODE=1' ERR

################################################################################
# Random secret generator -----------------------------------------------------
################################################################################
random_secret() {
  if openssl rand -base64 27 &>/dev/null; then
    # 36 printable chars after stripping '=' and '/' (URL‑safe-ish)
    openssl rand -base64 27 | tr -d /= | cut -c1-36
  else
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+=-[]{}<>?.,' </dev/urandom | head -c 36
  fi
}

################################################################################
# AWS IMDSv2 helpers ----------------------------------------------------------
################################################################################
fetch_creds() {
  log "🔐 Fetching AWS credentials (role: $AWS_ROLE_NAME)"
  local token creds_json
  token=$(curl -sSf -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
                http://169.254.169.254/latest/api/token) || {
    log "ERROR: Failed to get IMDSv2 token"
    EXIT_CODE=3
    return 1
  }
  creds_json=$(curl -sSf -H "X-aws-ec2-metadata-token: $token" \
                "http://169.254.169.254/latest/meta-data/iam/security-credentials/$AWS_ROLE_NAME") || {
    log "ERROR: Failed to get AWS credentials"
    EXIT_CODE=3
    return 1
  }
  [[ $(jq -r .Code <<< "$creds_json") == Success ]] || { 
    log "ERROR: creds response not Success"; 
    EXIT_CODE=3
    return 1
  }
  export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId <<< "$creds_json")
  export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<< "$creds_json")
  export AWS_SESSION_TOKEN=$(jq -r .Token <<< "$creds_json")
  export AWS_DEFAULT_REGION=$(curl -sSf -H "X-aws-ec2-metadata-token: $token" \
                                    http://169.254.169.254/latest/meta-data/placement/region) || {
    log "ERROR: Failed to get AWS region"
    EXIT_CODE=3
    return 1
  }
}
cleanup_creds() { unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_DEFAULT_REGION; }
trap cleanup_creds EXIT

################################################################################
# Certbot helpers -------------------------------------------------------------
################################################################################
certbot_action() {
  local overall_success=true
  local missing_certificates=()
  local existing_certificates=()

  log "🔍 Checking certificate status for ${#DOMAIN_ARRAY[@]} domain(s)"

  # First, check which certificates exist and which need to be created
  for domain in "${DOMAIN_ARRAY[@]}"; do
    if [[ -d "$LETSENCRYPT_DIR/live/$domain" ]]; then
      log "✅ Certificate exists for: $domain"
      existing_certificates+=("$domain")
    else
      log "🆕 Certificate missing for: $domain"
      missing_certificates+=("$domain")
    fi
  done

  # Create missing certificates first
  if [[ ${#missing_certificates[@]} -gt 0 ]]; then
    log "🆕 Creating ${#missing_certificates[@]} missing certificate(s)"
    
    # Build flags for certonly
    local certonly_flags=( --dns-route53 -m "$ACME_EMAIL" --agree-tos --non-interactive --quiet )
    
    # Add all missing domains to a single certonly command
    for domain in "${missing_certificates[@]}"; do
      certonly_flags+=( -d "$domain" )
    done

    # Staging mode overrides dry-run and adds test-cert flag
    if $STAGING; then
      certonly_flags+=( --test-cert )
      log "  ➜ Using Let's Encrypt staging environment (--test-cert)"
    elif $DRY_RUN; then
      certonly_flags+=( --dry-run )
    fi

    if certbot certonly "${certonly_flags[@]}"; then
      log "✅ Successfully created certificates for: ${missing_certificates[*]}"
      # Add newly created certificates to existing list for renewal
      existing_certificates+=("${missing_certificates[@]}")
    else
      log "❌ Failed to create certificates for: ${missing_certificates[*]}"
      overall_success=false
    fi
  fi

  # Now renew all existing certificates (including newly created ones)
  if [[ ${#existing_certificates[@]} -gt 0 ]]; then
    log "🔄 Renewing ${#existing_certificates[@]} existing certificate(s)"
    
    # Build flags for renew
    local renew_flags=( --quiet )
    
    if $FORCE; then
      renew_flags+=( --force-renewal )
    fi

    # Staging mode overrides dry-run and adds test-cert flag
    if $STAGING; then
      renew_flags+=( --test-cert )
      log "  ➜ Using Let's Encrypt staging environment (--test-cert)"
    elif $DRY_RUN; then
      renew_flags+=( --dry-run )
    fi

    if certbot renew "${renew_flags[@]}"; then
      log "✅ Successfully renewed certificates for: ${existing_certificates[*]}"
    else
      log "❌ Failed to renew certificates for: ${existing_certificates[*]}"
      overall_success=false
    fi
  fi

  log "📊 Certificate processing summary:"
  log "  ✅ Existing certificates: ${#existing_certificates[@]}"
  log "  🆕 New certificates created: ${#missing_certificates[@]}"
  log "  📋 Total domains processed: ${#DOMAIN_ARRAY[@]}"

  if [[ $overall_success == true ]]; then
    log "✅ All domains processed successfully"
    return 0
  else
    log "⚠️  Some domains failed to process"
    EXIT_CODE=4
    return 1
  fi
}

################################################################################
# Certificate validity helpers ------------------------------------------------
################################################################################
cert_days_left() {
  local pem=$1
  
  # Use OpenSSL to get expiration in a more portable way
  local exp_date
  exp_date=$(openssl x509 -noout -enddate -in "$pem" 2>/dev/null | cut -d= -f2)
  
  if [[ -z "$exp_date" ]]; then
    log "⚠️  Could not read certificate expiration date from $pem"
    return 0  # Assume renewal needed
  fi
  
  # Convert to epoch using a more portable approach
  local exp_ts
  if command -v gdate >/dev/null 2>&1; then
    # Use GNU date if available (more reliable)
    exp_ts=$(gdate -d "$exp_date" +%s 2>/dev/null || echo 0)
  elif date --version >/dev/null 2>&1; then
    # Try GNU date
    exp_ts=$(date -d "$exp_date" +%s 2>/dev/null || echo 0)
  else
    # Fallback: use a simple approach that works on most systems
    # Parse "Oct  3 18:07:43 2025 GMT" format
    local month day time year
    if [[ $exp_date =~ ^([A-Za-z]+)\ +([0-9]+)\ +([0-9:]+)\ +([0-9]+)\ +([A-Z]+)$ ]]; then
      month="${BASH_REMATCH[1]}"
      day="${BASH_REMATCH[2]}"
      time="${BASH_REMATCH[3]}"
      year="${BASH_REMATCH[4]}"
      
      # Convert month name to number
      case $month in
        Jan) month=01 ;; Feb) month=02 ;; Mar) month=03 ;; Apr) month=04 ;;
        May) month=05 ;; Jun) month=06 ;; Jul) month=07 ;; Aug) month=08 ;;
        Sep) month=09 ;; Oct) month=10 ;; Nov) month=11 ;; Dec) month=12 ;;
        *) month=01 ;; # Default to January if unknown
      esac
      
      # Pad day with leading zero if needed
      day=$(printf "%02d" "$day")
      
      # Try to parse with ISO format
      exp_ts=$(date -d "$year-$month-$day $time" +%s 2>/dev/null || echo 0)
    fi
  fi
  
  local now=$(date +%s)
  
  # If we still can't parse, assume renewal is needed
  if [[ $exp_ts -eq 0 ]]; then
    log "⚠️  Could not parse certificate expiration date: $exp_date"
    return 0  # Assume renewal needed
  fi
  
  echo $(((exp_ts-now)/86400))
}
needs_renewal() {
  [[ $FORCE == true ]] && return 0
  local pem="$LETSENCRYPT_DIR/live/${DOMAIN_ARRAY[0]}/cert.pem"
  [[ -f $pem ]] || return 0
  local left=$(cert_days_left "$pem")
  (( left <= RENEWAL_THRESHOLD_DAYS ))
}

################################################################################
# PFX generation & output prep -------------------------------------------------
################################################################################
create_pfx() {
  local domain=$1 password=$2 src="$LETSENCRYPT_DIR/live/$domain" tgt="$CERT_OUTPUT_DIR/$domain/cert.pfx"
  if [[ -z $password ]]; then
    log "ERROR: Password is required for PFX creation"
    return 1
  fi
  if openssl pkcs12 -export -in "$src/cert.pem" -inkey "$src/privkey.pem" \
                   -out "$tgt" -passout "pass:$password" -passin pass: 2>/dev/null; then
    chmod 400 "$tgt"
  else
    log "WARNING: Failed to create PFX for $domain"
  fi
}
prepare_output() {
  log "📦 Preparing output directory => $CERT_OUTPUT_DIR"
  local password="$1"
  for domain in "${DOMAIN_ARRAY[@]}"; do
    local src="$LETSENCRYPT_DIR/live/$domain" tgt="$CERT_OUTPUT_DIR/$domain"
    [[ -d $src ]] || { log "WARNING: missing $src"; continue; }
    install -d -m700 "$tgt"
    cp "$src"/{cert.pem,privkey.pem,fullchain.pem} "$tgt/" 2>/dev/null || true
    create_pfx "$domain" "$password"
  done
  # Canonical symlinks for consumers (pick first domain)
  ln -sf "${DOMAIN_ARRAY[0]}"/cert.pem      "$CERT_OUTPUT_DIR/cert.pem"
  ln -sf "${DOMAIN_ARRAY[0]}"/privkey.pem   "$CERT_OUTPUT_DIR/cert.key"
  ln -sf "${DOMAIN_ARRAY[0]}"/fullchain.pem "$CERT_OUTPUT_DIR/fullchain.pem"
  ln -sf "${DOMAIN_ARRAY[0]}"/cert.pfx      "$CERT_OUTPUT_DIR/cert.pfx"
}

################################################################################
# AWS Secrets Manager ---------------------------------------------------------
################################################################################
update_secret_password() {
  local new_password="$1"
  log "🔐 Storing new certificate password in AWS Secrets Manager (versioned)"

  local secret_json
  if secret_json=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_NAME" \
                    --query SecretString --output text 2>/dev/null); then
    secret_json=$(jq --arg p "$new_password" '.CERTIFICATE_PASSWORD=$p' <<<"$secret_json")
  else
    secret_json=$(jq -n --arg p "$new_password" '{CERTIFICATE_PASSWORD:$p}')
  fi

  # put-secret-value creates a new version each time – better auditing
  if echo "$secret_json" | aws secretsmanager put-secret-value \
    --secret-id "$AWS_SECRET_NAME" --secret-string file:///dev/stdin --output text &>/dev/null; then
    log "✅ Certificate password updated in AWS Secrets Manager"
  else
    log "❌ Failed to update certificate password in AWS Secrets Manager"
    EXIT_CODE=1
    return 1
  fi
}

################################################################################
# S3 distribution -------------------------------------------------------------
################################################################################
check_s3_files_exist() {
  if $DRY_RUN; then
    log "☁️  Dry‑run: assuming S3 files don't exist"
    return 1
  fi
  
  log "🔍 Checking if certificate files already exist in S3..."
  local all_exist=true
  
  for d in "${DOMAIN_ARRAY[@]}"; do
    local s3_path="s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/$d/"
    
    # Check if key certificate files exist in S3
    if ! aws s3 ls "$s3_path/cert.pem" &>/dev/null; then
      log "  ❌ Missing: $s3_path/cert.pem"
      all_exist=false
    elif ! aws s3 ls "$s3_path/privkey.pem" &>/dev/null; then
      log "  ❌ Missing: $s3_path/privkey.pem"
      all_exist=false
    elif ! aws s3 ls "$s3_path/fullchain.pem" &>/dev/null; then
      log "  ❌ Missing: $s3_path/fullchain.pem"
      all_exist=false
    elif ! aws s3 ls "$s3_path/cert.pfx" &>/dev/null; then
      log "  ❌ Missing: $s3_path/cert.pfx"
      all_exist=false
    else
      log "  ✅ All files exist for: $d"
    fi
  done
  
  if [[ "$all_exist" == "true" ]]; then
    log "✅ All certificate files already exist in S3"
    return 0
  else
    log "❌ Some certificate files missing in S3"
    return 1
  fi
}

upload_to_s3() {
  if $DRY_RUN; then
    log "☁️  Dry‑run: skip S3 upload"
    return
  fi
  log "☁️  Uploading artefacts to s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/"
  
  local upload_failed=false
  for d in "${DOMAIN_ARRAY[@]}"; do
    local src="$LETSENCRYPT_DIR/live/$d" dst="s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/$d/"
    if aws s3 cp --only-show-errors --recursive "$src" "$dst"; then
      log "✅ Uploaded certificate files for $d"
    else
      log "❌ Failed to upload certificate files for $d"
      upload_failed=true
    fi
    
    if [[ -f "$CERT_OUTPUT_DIR/$d/cert.pfx" ]]; then
      if aws s3 cp --only-show-errors "$CERT_OUTPUT_DIR/$d/cert.pfx" "$dst"; then
        log "✅ Uploaded PFX file for $d"
      else
        log "❌ Failed to upload PFX file for $d"
        upload_failed=true
      fi
    fi
  done
  
  if [[ "$upload_failed" == "true" ]]; then
    log "❌ S3 upload completed with errors"
    EXIT_CODE=5
    return 1
  else
    log "✅ S3 upload completed successfully"
  fi
}

################################################################################
# Main ------------------------------------------------------------------------
################################################################################
main() {
  log "🚀 Starting main certificate renewal process"
  status IN_PROGRESS "Renewal task started (threshold ${RENEWAL_THRESHOLD_DAYS}d)"
  
  if ! fetch_creds; then
    log "❌ Failed to fetch AWS credentials"
    status FAILED "AWS credential error"
    exit $EXIT_CODE
  fi

  [[ -d $LETSENCRYPT_DIR ]] || { 
    log "ERROR: $LETSENCRYPT_DIR missing (EBS not mounted?)"; 
    EXIT_CODE=1
    status FAILED "LetsEncrypt directory missing"
    exit $EXIT_CODE
  }

  if needs_renewal; then
    log "🔧 Renewal required"
    local new_pass=$(random_secret)
    
    if ! $STAGING && ! $DRY_RUN; then
      if ! update_secret_password "$new_pass"; then
        log "❌ Failed to update certificate password"
        status FAILED "Password update error"
        exit $EXIT_CODE
      fi
    else
      if $STAGING; then
        log "🔐 Staging mode: skipping password update in AWS Secrets Manager"
      elif $DRY_RUN; then
        log "🔐 Dry-run mode: skipping password update in AWS Secrets Manager"
      fi
    fi
    
    if ! certbot_action; then
      log "❌ Certbot action failed"
      status FAILED "Certbot error"
      exit $EXIT_CODE
    fi
    
    prepare_output "$new_pass"
    
    if ! upload_to_s3; then
      log "❌ S3 upload failed"
      status FAILED "S3 upload error"
      exit $EXIT_CODE
    fi

    # Write renewal-status.json to S3
    log "☁️  Writing renewal-status.json to S3 (renewal occurred)"
    status_json="$(jq -n \
      --argjson occurred true \
      --argjson domains "$(printf '%s\n' "${DOMAIN_ARRAY[@]}" | jq -R . | jq -s .)" \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{renewal_occurred: $occurred, renewed_domains: $domains, timestamp: $ts}')"
    "${DRY_RUN}" == "true" || echo "$status_json" | aws s3 cp - "s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/renewal-status.json" --content-type application/json --only-show-errors && \
      log "✅ renewal-status.json uploaded"
    # Post‑renew hook placeholder (e.g., send SIGUSR1 to nginx for reload)
  else
    log "✅ Certificates healthy (> ${RENEWAL_THRESHOLD_DAYS}d)"
    # Check if files are already uploaded to S3
    if check_s3_files_exist; then
      log "✅ Certificate files already exist in S3 - no action needed"
      # Write renewal-status.json to S3 (no renewal)
      log "☁️  Writing renewal-status.json to S3 (no renewal)"
      status_json="$(jq -n \
        --argjson occurred false \
        --argjson domains '[]' \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{renewal_occurred: $occurred, renewed_domains: $domains, timestamp: $ts}')"
      "${DRY_RUN}" == "true" || echo "$status_json" | aws s3 cp - "s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/renewal-status.json" --content-type application/json --only-show-errors && \
        log "✅ renewal-status.json uploaded"
    else
      log "📤 Certificate files missing in S3 - creating new PFX and uploading"
      local new_pass=$(random_secret)
      if ! $STAGING && ! $DRY_RUN; then
        if ! update_secret_password "$new_pass"; then
          log "❌ Failed to update certificate password"
          status FAILED "Password update error"
          exit $EXIT_CODE
        fi
      else
        if $STAGING; then
          log "🔐 Staging mode: skipping password update in AWS Secrets Manager"
        elif $DRY_RUN; then
          log "🔐 Dry-run mode: skipping password update in AWS Secrets Manager"
        fi
      fi
      prepare_output "$new_pass"
      if ! upload_to_s3; then
        log "❌ S3 upload failed"
        status FAILED "S3 upload error"
        exit $EXIT_CODE
      fi
      # Write renewal-status.json to S3 (no renewal, but files uploaded)
      log "☁️  Writing renewal-status.json to S3 (no renewal, files uploaded)"
      status_json="$(jq -n \
        --argjson occurred false \
        --argjson domains '[]' \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{renewal_occurred: $occurred, renewed_domains: $domains, timestamp: $ts}')"
      "${DRY_RUN}" == "true" || echo "$status_json" | aws s3 cp - "s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID/renewal-status.json" --content-type application/json --only-show-errors && \
        log "✅ renewal-status.json uploaded"
    fi
  fi

  status SUCCESS "Certificate process complete"
  log "🎉 Certificate renewal completed successfully"
  exit 0
}

main "$@"
