#!/usr/bin/env bash
###############################################################################
# renew-certificate.sh — ACME automation for multi-domain stacks in AWS (Route 53)
#
# Exit codes:
#   0  Success
#   1  Configuration error
#   2  Missing dependency
#   3  AWS credential error
#   4  Certbot error
#   5  S3 upload error
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

###############################################################################
# Constants
###############################################################################
readonly SCRIPT_NAME=${0##*/}
readonly LETSENCRYPT_DIR=/etc/letsencrypt
readonly DEFAULT_RENEW_THRESHOLD_DAYS=10
readonly LOG_DIR=/var/log/certificate-manager
readonly LOG_FILE=$LOG_DIR/certificate-renewal.log
readonly STATUS_FILE=$LOG_DIR/certificate-renewal.status
FORCE_UPLOAD=${FORCE_UPLOAD:-false}

###############################################################################
# Logging helpers
###############################################################################
_ts() { date '+%F %T'; }
log()   { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
status(){ printf '%s: %s at %s\n' "$1" "$2" "$(_ts)" >"$STATUS_FILE"; log "STATUS ⇢ $1 — $2"; }

trap 'status FAILED "line $LINENO exited with code $?"; exit 1' ERR
mkdir -p "$LOG_DIR"

###############################################################################
# CLI
###############################################################################
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--force] [--dry-run] [--staging]

Options:
  --force     Renew even if certificates are still valid.
  --dry-run   Skip certbot, S3 and Secrets Manager writes.
  --staging   Use Let's Encrypt staging environment.
  -h, --help  Show this help.
EOF
}

FORCE=false DRY_RUN=false STAGING=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)   FORCE=true   ;;
    --dry-run) DRY_RUN=true ;;
    --staging) STAGING=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
  shift
done

###############################################################################
# Dependency checks
###############################################################################
need_cmd() { command -v "$1" &>/dev/null || { log "Missing dependency: $1"; exit 2; }; }
for c in jq aws openssl certbot curl; do need_cmd "$c"; done

###############################################################################
# Secret management
###############################################################################
import_secret() {
  local name=$1 path=/run/secrets/$1
  [[ -z ${!name-} && -r $path ]] && export "$name"="$(<"$path")"
}

for v in AWS_ROLE_NAME CERTIFICATE_STORE ACME_EMAIL DOMAINS_NAMES AWS_SECRET_NAME; do
  import_secret "$v"
  [[ -n ${!v-} ]] || { log "Required variable not set: $v"; exit 1; }
done

###############################################################################
# Derived globals
###############################################################################
RENEWAL_THRESHOLD_DAYS=${RENEWAL_THRESHOLD_DAYS:-$DEFAULT_RENEW_THRESHOLD_DAYS}
CERT_PREFIX=${CERT_PREFIX:-certificates}
RUN_ID=${RUN_ID:-$(date +%Y%m%d%H%M%S)}
CERT_OUTPUT_DIR=/app/certs
IFS=',' read -r -a DOMAINS <<<"$DOMAINS_NAMES"

###############################################################################
# Utility functions
###############################################################################
random_secret() { openssl rand -base64 27 | tr -d /= | cut -c1-36; }

metadata() {
  local token url=$1
  token=$(curl -sf -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
           http://169.254.169.254/latest/api/token)
  curl -sf -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254$url"
}

assume_role() {
  log "Fetching AWS credentials for role: $AWS_ROLE_NAME"
  local creds
  creds=$(metadata "/latest/meta-data/iam/security-credentials/$AWS_ROLE_NAME") || exit 3
  [[ $(jq -r .Code <<<"$creds") == Success ]] || exit 3

  export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId    <<<"$creds")
  export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey <<<"$creds")
  export AWS_SESSION_TOKEN=$(jq -r .Token          <<<"$creds")
  export AWS_DEFAULT_REGION=$(metadata "/latest/meta-data/placement/region")
}

days_until_expiry() {
  local pem=$1 exp
  exp=$(openssl x509 -enddate -noout -in "$pem" | cut -d= -f2)
  (( ($(date -d "$exp" +%s) - $(date +%s)) / 86400 ))
}

needs_renewal() {
  [[ $FORCE == true ]] && return 0
  local pem=$LETSENCRYPT_DIR/live/${DOMAINS[0]}/cert.pem
  [[ ! -f $pem ]] || (( $(days_until_expiry "$pem") <= RENEWAL_THRESHOLD_DAYS ))
}

certbot_run() {
  local args=(--dns-route53 -m "$ACME_EMAIL" --agree-tos --non-interactive --quiet)
  $STAGING && args+=(--test-cert)
  $DRY_RUN && args+=(--dry-run)

  certbot renew "${args[@]}" || exit 4
}

make_pfx() {
  local domain=$1 pw=$2 dir=$CERT_OUTPUT_DIR/$domain
  install -d -m 700 "$dir"
  cp "$LETSENCRYPT_DIR/live/$domain"/{cert.pem,privkey.pem,fullchain.pem} "$dir"/
  openssl pkcs12 -export \
    -in "$dir/cert.pem" -inkey "$dir/privkey.pem" \
    -out "$dir/cert.pfx" -passout "pass:$pw" -passin pass:
  chmod 400 "$dir/cert.pfx"
}

upload_s3() {
  $DRY_RUN && { log "Dry-run: skipping upload"; return; }
  local dest=s3://$CERTIFICATE_STORE/$CERT_PREFIX/$RUN_ID
  for d in "${DOMAINS[@]}"; do
    aws s3 cp --only-show-errors --recursive "$LETSENCRYPT_DIR/live/$d" "$dest/$d/"
    aws s3 cp --only-show-errors "$CERT_OUTPUT_DIR/$d/cert.pfx" "$dest/$d/"
  done
  echo "$RUN_ID" | aws s3 cp - "$dest/../last-renewal-run-id" --only-show-errors
}

update_secret() {
  $DRY_RUN && return
  local json
  if json=$(aws secretsmanager get-secret-value --secret-id "$AWS_SECRET_NAME" \
              --query SecretString --output text 2>/dev/null); then
    json=$(jq --arg p "$1" '.CERTIFICATE_PASSWORD=$p' <<<"$json")
  else
    json=$(jq -n --arg p "$1" '{CERTIFICATE_PASSWORD:$p}')
  fi
  echo "$json" | \
    aws secretsmanager put-secret-value --secret-id "$AWS_SECRET_NAME" \
    --secret-string file:///dev/stdin --output text >/dev/null
}

###############################################################################
# Main
###############################################################################
main() {
  status IN_PROGRESS "started"
  assume_role

  if needs_renewal || [[ $FORCE_UPLOAD == true ]]; then
    [[ $FORCE_UPLOAD == true ]] && log "FORCE_UPLOAD=true — uploading without renewal"
    [[ $FORCE_UPLOAD == false ]] && certbot_run

    local pw=$(make_secret)
    update_secret "$pw"
    for d in "${DOMAINS[@]}"; do make_pfx "$d" "$pw"; done
    upload_s3
    status SUCCESS "$([[ $FORCE_UPLOAD == true ]] && echo 'forced upload' || echo 'renewed')"
  else
    log "certificates healthy (> $THRESHOLD_DAYS d)"
    status SUCCESS "no renewal needed"
  fi
}

main "$@"
