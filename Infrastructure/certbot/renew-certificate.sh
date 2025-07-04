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
# Usage -----------------------------------------------------------------------
################################################################################
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--force] [--dry-run]

Options:
  --force        Renew certificates regardless of remaining validity.
  --dry-run      Execute everything except the final Certbot/S3/AWS writes.
  -h, --help     Show this help.
EOF
}

################################################################################
# CLI arguments ----------------------------------------------------------------
################################################################################
FORCE=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=true ; shift ;;
    --dry-run) DRY_RUN=true ; shift ;;
    -h|--help) usage ; exit 0 ;;
    *) echo "Unknown option: $1" >&2 ; usage ; exit 1 ;;
  esac
done

################################################################################
# Helper: import a Swarm secret if env‑var is empty ----------------------------
################################################################################
import_secret() {
  local var=$1 path="/run/secrets/$var"
  [[ -z ${!var:-} && -f $path ]] && export "$var"="$(<"$path")"
}

# Mandatory/optional secrets
for s in AWS_ROLE_NAME CERTIFICATE_STORE ACME_EMAIL DOMAINS_NAMES AWS_SECRET_NAME; do
  import_secret "$s"
done

################################################################################
# Verify mandatory dependencies & variables -----------------------------------
################################################################################
need_cmd() { 
  command -v "$1" &>/dev/null || { 
    echo "ERROR: '$1' not found in PATH" >&2 
    EXIT_CODE=2
    return 1
  }; 
}

for bin in jq aws openssl certbot curl; do 
  need_cmd "$bin" || exit $EXIT_CODE
done

[[ -n ${CERTIFICATE_STORE:-}       ]] || { echo "CERTIFICATE_STORE is required (secret or env)" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${ACME_EMAIL:-}           ]] || { echo "ACME_EMAIL is required" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${AWS_ROLE_NAME:-}   ]] || { echo "AWS_ROLE_NAME is required" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${DOMAINS_NAMES:-}         ]] || { echo "DOMAINS_NAMES is required (comma‑separated)" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }
[[ -n ${AWS_SECRET_NAME:-} ]] || { echo "AWS_SECRET_NAME is required" >&2 ; EXIT_CODE=1; exit $EXIT_CODE; }

RENEWAL_THRESHOLD_DAYS=${RENEWAL_THRESHOLD_DAYS:-$DEFAULT_RENEWAL_THRESHOLD_DAYS}
CERT_PREFIX=${CERT_PREFIX:-certificates}
RUN_ID=${RUN_ID:-$(date +%Y%m%d%H%M%S)}
LOG_DIR="/var/log/certificate-manager"
LOG_FILE="${LOG_DIR}/certificate-renewal.log"
STATUS_FILE="${LOG_DIR}/renew-certificate.status"
CERT_OUTPUT_DIR="/app/certs"

IFS=',' read -r -a DOMAIN_ARRAY <<< "$DOMAINS_NAMES"

mkdir -p "$LOG_DIR" /var/{lib,log}/letsencrypt "$CERT_OUTPUT_DIR"

################################################################################
# Logging utilities -----------------------------------------------------------
################################################################################
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
status() {
  printf '%s: %s at %s\n' "$1" "$2" "$(_ts)" >"$STATUS_FILE"
  log "STATUS ➜ $1 – $2"
}
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
  echo
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
  # Build domain flags – certbot supports comma separation only for --renew-by-default
  local flags=()
  for d in "${DOMAIN_ARRAY[@]}"; do flags+=( -d "$d" ); done

  if $FORCE; then
    flags+=( --force-renewal )
  fi

  if $DRY_RUN; then
    flags+=( --dry-run )
  fi

  if [[ -d "$LETSENCRYPT_DIR/live/${DOMAIN_ARRAY[0]}" ]]; then
    log "🔄 Running certbot renew for ${#DOMAIN_ARRAY[@]} domain(s)"
    if certbot renew --deploy-hook "true" --quiet "${flags[@]}"; then
      log "✅ Certbot renew completed successfully"
    else
      log "❌ Certbot renew failed"
      EXIT_CODE=4
      return 1
    fi
  else
    log "🆕 Initial certificate request for ${#DOMAIN_ARRAY[@]} domain(s)"
    if certbot certonly --dns-route53 -m "$ACME_EMAIL" --agree-tos --non-interactive \
                       --quiet "${flags[@]}"; then
      log "✅ Certbot certonly completed successfully"
    else
      log "❌ Certbot certonly failed"
      EXIT_CODE=4
      return 1
    fi
  fi
}

################################################################################
# Certificate validity helpers ------------------------------------------------
################################################################################
cert_days_left() {
  local pem=$1 exp exp_ts now
  exp=$(openssl x509 -noout -enddate -in "$pem" | cut -d= -f2)
  exp_ts=$(date -d "$exp" +%s)
  now=$(date +%s)
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
  local pass_arg=[[ -n $password ]] && pass_arg="pass:$password" || pass_arg="pass:"
  if openssl pkcs12 -export -in "$src/cert.pem" -inkey "$src/privkey.pem" \
                   -out "$tgt" -passout "$pass_arg" -passin pass: -quiet; then
    chmod 400 "$tgt"
  else
    log "WARNING: Failed to create PFX for $domain"
  fi
}
prepare_output() {
  log "📦 Preparing output directory => $CERT_OUTPUT_DIR"
  local password="$1"
  for d in "${DOMAIN_ARRAY[@]}"; do
    local src="$LETSENCRYPT_DIR/live/$d" tgt="$CERT_OUTPUT_DIR/$d"
    [[ -d $src ]] || { log "WARNING: missing $src"; continue; }
    install -d -m700 "$tgt"
    cp "$src"/{cert.pem,privkey.pem,fullchain.pem} "$tgt/" 2>/dev/null || true
    create_pfx "$d" "$password"
  done
  # Canonical symlinks for consumers (pick first domain)
  ln -sf "${DOMAIN_ARRAY[0]}"/cert.pem      "$CERT_OUTPUT_DIR/cert.pem"
  ln -sf "${DOMAIN_ARRAY[0]}"/privkey.pem   "$CERT_OUTPUT_DIR/cert.key"
  ln -sf "${DOMAIN_ARRAY[0]}"/fullchain.pem "$CERT_OUTPUT_DIR/fullchain.pem"
  ln -sf "${DOMAIN_ARRAY[0]}"/cert.pfx      "$CERT_OUTPUT_DIR/cert.pfx"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$CERT_OUTPUT_DIR/last-updated.txt"
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
upload_to_s3() {
  $DRY_RUN && { log "☁️  Dry‑run: skip S3 upload"; return; }
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
    
    if ! update_secret_password "$new_pass"; then
      log "❌ Failed to update certificate password"
      status FAILED "Password update error"
      exit $EXIT_CODE
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
    # Post‑renew hook placeholder (e.g., send SIGUSR1 to nginx for reload)
  else
    log "✅ Certificates healthy (> ${RENEWAL_THRESHOLD_DAYS}d)"
    prepare_output  # still refresh timestamps/hashes
  fi

  status SUCCESS "Certificate process complete"
  log "🎉 Certificate renewal completed successfully"
  exit 0
}

main "$@"
