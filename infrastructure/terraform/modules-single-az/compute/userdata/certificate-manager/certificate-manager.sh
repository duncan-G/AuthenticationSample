#!/usr/bin/env bash
###############################################################################
# certificate-manager.sh — Self-signed certificate management for Docker Swarm
#
# - Runs on the Swarm leader.
# - Regenerates self-signed certs when missing or expiring soon.
# - Pushes password to AWS Secrets Manager, updates Docker secrets, and rolls services.
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

###############################################################################
# Defaults / constants
###############################################################################
readonly SCRIPT_NAME=${0##*/}
readonly LOG_DIR="/var/log/certificate-manager"
readonly STATUS_FILE="$LOG_DIR/certificate-manager.status"
readonly RENEWAL_THRESHOLD_DAYS=30         # renew when cert expires in <= 30 days
readonly CERT_VALIDITY_DAYS=45
CERT_DIR="${CERT_DIR:-/var/lib/certificate-manager/certs}"

# files we generate
readonly CERT_FILES=("aspnetapp.pfx" "ca.crt" "cert.key" "cert.pem")
# secrets we maintain (same names)
readonly DOCKER_SECRETS=("aspnetapp.pfx" "ca.crt" "cert.key" "cert.pem")
readonly CERT_PASSWORD_KEY="Infrastructure_CERTIFICATE_PASSWORD"

mkdir -p "$LOG_DIR"

###############################################################################
# Logging / status
###############################################################################
ts() { date '+%F %T'; }
log() { printf '[ %s ] %s\n' "$(ts)" "$*" >&2; }
status() { printf '%s: %s at %s\n' "$1" "$2" "$(ts)" >"$STATUS_FILE"; log "STATUS ⇢ $1 — $2"; }
fatal() { log "ERROR: $*"; exit 1; }

trap 'status FAILED "line $LINENO exited with code $?"; exit 1' ERR

###############################################################################
# CLI
###############################################################################
DAEMON=false
FORCE=false
OUTPUT_DIR=""

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--daemon] [--force] [--output-dir PATH]

Env:
  AWS_SECRET_NAME  (required)
  AWS_REGION       (required)
  DOMAIN_NAME      (default: localhost)
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --daemon)     DAEMON=true ;;
    --force)      FORCE=true ;;
    --output-dir) shift; OUTPUT_DIR=${1:-} ;;
    -h|--help)    usage; exit 0 ;;
    *)            usage; exit 1 ;;
  esac
  shift
done

###############################################################################
# Helpers
###############################################################################
need_cmd() { command -v "$1" &>/dev/null || { log "Missing: $1"; exit 2; }; }

for c in aws openssl docker jq; do need_cmd "$c"; done
[[ -n ${AWS_SECRET_NAME:-} ]] || fatal "AWS_SECRET_NAME required"
[[ -n ${AWS_REGION:-} ]] || fatal "AWS_REGION required"

DOMAIN_NAME=${DOMAIN_NAME:-localhost}

# figure target dir once
target_dir() {
  if [[ -n "$OUTPUT_DIR" ]]; then
    echo "$OUTPUT_DIR"
  else
    echo "$CERT_DIR"
  fi
}

###############################################################################
# Swarm manager checks
###############################################################################
check_swarm_leader() {
  docker info &>/dev/null || fatal "Docker not running / not accessible"

  local swarm_state
  swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
  [[ "$swarm_state" == "active" ]] || fatal "Not part of Swarm (state: $swarm_state)"

  local is_mgr
  is_mgr=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)
  [[ "$is_mgr" == "true" ]] || fatal "Not a Swarm manager"

  local node_id leader_id
  node_id=$(docker info --format '{{.Swarm.NodeID}}' 2>/dev/null)
  leader_id=$(docker node ls --filter role=manager --format '{{.ID}} {{.ManagerStatus}}' | awk '$2 ~ /Leader/ {print $1; exit}')

  if [[ -z "$leader_id" ]]; then
    fatal "Could not determine Swarm leader"
  fi

  if [[ "$node_id" != "$leader_id" ]]; then
    log "Not Swarm leader (this: $node_id, leader: $leader_id); exiting gracefully"
    exit 0
  fi

  log "Confirmed: running on Swarm leader ($node_id)"
}

###############################################################################
# Cert inspection
###############################################################################
is_cert_expiring() {
  local cert_file="$1" threshold_days="$2"
  [[ -f "$cert_file" ]] || return 0

  local expiry
  expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2) || return 0
  local expiry_epoch
  expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null) || return 0
  local now_epoch days_left
  now_epoch=$(date +%s)
  days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
  log "Cert $cert_file expires in $days_left days (threshold $threshold_days)"
  [[ $days_left -le $threshold_days ]]
}

needs_certificate_renewal() {
  [[ $FORCE == true ]] && return 0

  local dir
  dir="$(target_dir)"
  for f in "${CERT_FILES[@]}"; do
    [[ -f "$dir/$f" ]] || { log "Missing $f"; return 0; }
  done

  # Check only actual certs
  for f in cert.pem ca.crt; do
    if is_cert_expiring "$dir/$f" "$RENEWAL_THRESHOLD_DAYS"; then
      log "$f needs renewal"
      return 0
    fi
  done

  return 1
}

###############################################################################
# Generation
###############################################################################
random_password() { openssl rand -base64 32 | tr -d "=+/" | cut -c1-32; }

generate_certificates() {
  local password="$1" domain="$2"
  local dir
  dir="$(target_dir)"
  mkdir -p "$dir"
  rm -f "$dir"/*

  log "Generating self-signed certs in $dir for $domain"

  openssl genrsa -out "$dir/cert.key" 2048
  openssl req -new -key "$dir/cert.key" -out "$dir/cert.csr" \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$domain"
  openssl x509 -req -in "$dir/cert.csr" -signkey "$dir/cert.key" \
    -out "$dir/cert.pem" -days "$CERT_VALIDITY_DAYS"

  cp "$dir/cert.pem" "$dir/ca.crt"
  cp "$dir/ca.crt" "$dir/ca.pem"

  openssl pkcs12 -export -out "$dir/aspnetapp.pfx" \
    -inkey "$dir/cert.key" -in "$dir/cert.pem" \
    -passout "pass:$password"

  rm -f "$dir/cert.csr"

  chmod 600 "$dir"/* 2>/dev/null || true
  chmod 644 "$dir"/{ca.crt,ca.pem,cert.pem} 2>/dev/null || true

  log "Certificates generated"
}

###############################################################################
# AWS: store password JSON
###############################################################################
update_aws_secret() {
  local password="$1"

  log "Updating AWS Secrets Manager: $AWS_SECRET_NAME"
  local current
  if current=$(aws secretsmanager get-secret-value \
      --secret-id "$AWS_SECRET_NAME" \
      --region "$AWS_REGION" \
      --query SecretString --output text 2>/dev/null); then

    local new_json
    new_json=$(jq --arg k "$CERT_PASSWORD_KEY" --arg v "$password" '. + {($k): $v}' <<<"$current")
    printf '%s' "$new_json" | aws secretsmanager put-secret-value \
      --secret-id "$AWS_SECRET_NAME" \
      --region "$AWS_REGION" \
      --secret-string file:///dev/stdin >/dev/null
  else
    local new_json
    new_json=$(jq -n --arg v "$password" '{ "'"$CERT_PASSWORD_KEY"'": $v }')
    printf '%s' "$new_json" | aws secretsmanager create-secret \
      --name "$AWS_SECRET_NAME" \
      --region "$AWS_REGION" \
      --secret-string file:///dev/stdin >/dev/null
  fi
  log "AWS secret updated"
}

###############################################################################
# Docker secrets + service refresh
###############################################################################
update_docker_secrets() {
  local dir
  dir="$(target_dir)"
  log "Updating Docker secrets from $dir"

  for s in "${DOCKER_SECRETS[@]}"; do
    if docker secret inspect "$s" &>/dev/null; then
      docker secret rm "$s" || log "Warning: failed to remove secret $s"
    fi
  done

  for f in "${CERT_FILES[@]}"; do
    if [[ -f "$dir/$f" ]]; then
      docker secret create "$f" "$dir/$f" || fatal "Failed to create secret $f"
    else
      log "Warning: file missing for secret $f"
    fi
  done

  log "Docker secrets updated"
}

restart_services() {
  local services=("envoy_app" "auth_app" "greeter_app")
  log "Restarting Swarm services that use certs"
  for s in "${services[@]}"; do
    if docker service inspect "$s" &>/dev/null; then
      docker service update --force "$s" || log "Warning: failed to restart $s"
    else
      log "Service $s not found, skipping"
    fi
  done
  log "Service restart done"
}

###############################################################################
# Core
###############################################################################
manage_certificates() {
  status IN_PROGRESS "checking"

  if ! needs_certificate_renewal; then
    log "Certificates OK — no action"
    status SUCCESS "valid"
    return 0
  fi

  status IN_PROGRESS "renewing"
  log "Certificate renewal required"

  local password
  password=$(random_password)

  generate_certificates "$password" "$DOMAIN_NAME"

  update_aws_secret "$password"
  update_docker_secrets
  restart_services

  status SUCCESS "renewed"
  log "Certificate management done"
}

###############################################################################
# Main
###############################################################################
main() {
  log "Starting certificate manager"

  check_swarm_leader

  manage_certificates
}

main "$@"
