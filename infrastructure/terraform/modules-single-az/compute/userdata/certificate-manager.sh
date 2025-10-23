#!/usr/bin/env bash
###############################################################################
# certificate-manager.sh — Self-signed certificate management for Docker Swarm
#
# This script manages self-signed certificates for the AuthSample project.
# It checks if certificates are missing or expiring (within 30 days), generates
# new self-signed certificates if needed, and updates Docker secrets.
#
# Exit codes:
#   0  Success
#   1  Configuration error
#   2  Missing dependency
#   3  AWS credential error
#   4  Certificate generation error
#   5  Docker secret error
###############################################################################

set -Eeuo pipefail
shopt -s inherit_errexit nullglob

###############################################################################
# Constants
###############################################################################
readonly SCRIPT_NAME=${0##*/}
readonly CERT_DIR="/var/lib/certificate-manager/certs"
readonly LOG_DIR="/var/log/certificate-manager"
readonly LOG_FILE="$LOG_DIR/certificate-manager.log"
readonly STATUS_FILE="$LOG_DIR/certificate-manager.status"
readonly RENEWAL_THRESHOLD_DAYS=30
readonly CERT_VALIDITY_DAYS=365

# Certificate files
readonly CERT_FILES=("aspnetapp.pfx" "ca.crt" "cert.key" "cert.pem")
readonly DOCKER_SECRETS=("aspnetapp.pfx" "ca.crt" "cert.key" "cert.pem")

# AWS Secrets Manager key for certificate password
readonly CERT_PASSWORD_KEY="Infrastructure_CERTIFICATE_PASSWORD"

###############################################################################
# Logging helpers
###############################################################################
_ts() { date '+%F %T'; }
log()   { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
status(){ printf '%s: %s at %s\n' "$1" "$2" "$(_ts)" >"$STATUS_FILE"; log "STATUS ⇢ $1 — $2"; }
fatal()   { log "ERROR: $*"; exit 1; }

trap 'status FAILED "line $LINENO exited with code $?"; exit 1' ERR
mkdir -p "$LOG_DIR" "$CERT_DIR"

###############################################################################
# CLI
###############################################################################
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [--daemon] [--force]

Options:
  --daemon   Run in daemon mode (continuous monitoring)
  --force    Force certificate regeneration even if valid
  -h, --help Show this help.

Environment Variables:
  AWS_SECRET_NAME    - Required: AWS Secrets Manager secret name
  AWS_REGION         - Optional: AWS region (default: us-east-1)
  DOMAIN_NAME        - Optional: Domain name for certificate (default: localhost)
EOF
}

DAEMON=false FORCE=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --daemon)   DAEMON=true   ;;
    --force)    FORCE=true    ;;
    -h|--help)  usage; exit 0 ;;
    *)          usage; exit 1 ;;
  esac
  shift
done

###############################################################################
# Dependency checks
###############################################################################
need_cmd() { command -v "$1" &>/dev/null || { log "Missing dependency: $1"; exit 2; }; }
for c in aws openssl docker jq; do need_cmd "$c"; done

###############################################################################
# Environment validation
###############################################################################
[[ -n ${AWS_SECRET_NAME:-} ]] || fatal "AWS_SECRET_NAME environment variable is required"
AWS_REGION=${AWS_REGION:-us-east-1}
DOMAIN_NAME=${DOMAIN_NAME:-localhost}

log "Configuration: AWS_SECRET_NAME=$AWS_SECRET_NAME, AWS_REGION=$AWS_REGION, DOMAIN_NAME=$DOMAIN_NAME"

###############################################################################
# Docker Swarm validation
###############################################################################
check_swarm_manager() {
    # Check if Docker is running
    if ! docker info &>/dev/null; then
        fatal "Docker is not running or not accessible"
    fi
    
    # Check if this is a Docker Swarm node
    local swarm_state
    swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
    if [[ "$swarm_state" != "active" ]]; then
        fatal "This node is not part of a Docker Swarm cluster (state: $swarm_state)"
    fi
    
    # Check if this is a manager node
    local node_role
    node_role=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)
    if [[ "$node_role" != "true" ]]; then
        fatal "This node is not a Docker Swarm manager"
    fi
    
    # Check if this is the lead manager
    local node_id
    node_id=$(docker info --format '{{.Swarm.NodeID}}' 2>/dev/null)
    
    local leader_id
    leader_id=$(docker node ls --format '{{.ID}}' --filter role=manager --filter availability=active | head -n1)
    
    if [[ "$node_id" != "$leader_id" ]]; then
        log "This is not the lead Docker Swarm manager (node: $node_id, leader: $leader_id)"
        log "Certificate management should only run on the lead manager"
        exit 0  # Exit gracefully, not an error
    fi
    
    log "Confirmed: Running on lead Docker Swarm manager (node: $node_id)"
}

###############################################################################
# Utility functions
###############################################################################
random_password() { openssl rand -base64 32 | tr -d "=+/" | cut -c1-32; }

# Check if certificate is expiring within threshold days
is_cert_expiring() {
    local cert_file="$1"
    local threshold_days="$2"
    
    [[ -f "$cert_file" ]] || return 0  # Missing cert needs renewal
    
    local expiry_date
    if ! expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2); then
        log "Failed to read certificate expiry date from $cert_file"
        return 0  # Assume needs renewal if can't read
    fi
    
    local expiry_epoch
    if ! expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null); then
        log "Failed to parse certificate expiry date: $expiry_date"
        return 0  # Assume needs renewal if can't parse
    fi
    
    local current_epoch
    current_epoch=$(date +%s)
    local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
    
    log "Certificate expires in $days_until_expiry days (threshold: $threshold_days)"
    [[ $days_until_expiry -le $threshold_days ]]
}

# Check if all required certificates exist and are valid
needs_certificate_renewal() {
    [[ $FORCE == true ]] && return 0
    
    for cert_file in "${CERT_FILES[@]}"; do
        local full_path="$CERT_DIR/$cert_file"
        if ! is_cert_expiring "$full_path" "$RENEWAL_THRESHOLD_DAYS"; then
            log "Certificate $cert_file is valid"
        else
            log "Certificate $cert_file needs renewal"
            return 0
        fi
    done
    
    return 1  # All certificates are valid
}

# Generate self-signed certificates
generate_certificates() {
    local cert_password="$1"
    local domain="$2"
    
    log "Generating self-signed certificates for domain: $domain"
    
    # Clean up existing certificates
    rm -rf "$CERT_DIR"/*
    
    # Generate private key
    openssl genrsa -out "$CERT_DIR/cert.key" 2048
    
    # Generate certificate signing request
    openssl req -new -key "$CERT_DIR/cert.key" -out "$CERT_DIR/cert.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$domain"
    
    # Generate self-signed certificate
    openssl x509 -req -in "$CERT_DIR/cert.csr" -signkey "$CERT_DIR/cert.key" \
        -out "$CERT_DIR/cert.pem" -days "$CERT_VALIDITY_DAYS"
    
    # Create CA certificate (copy of cert.pem for this self-signed setup)
    cp "$CERT_DIR/cert.pem" "$CERT_DIR/ca.crt"
    
    # Generate PFX file with password
    openssl pkcs12 -export -out "$CERT_DIR/aspnetapp.pfx" \
        -inkey "$CERT_DIR/cert.key" -in "$CERT_DIR/cert.pem" \
        -passout "pass:$cert_password"
    
    # Clean up CSR file
    rm -f "$CERT_DIR/cert.csr"
    
    # Set proper permissions
    chmod 600 "$CERT_DIR"/*
    
    log "Self-signed certificates generated successfully"
}

# Update AWS Secrets Manager with certificate password
update_aws_secret() {
    local password="$1"
    
    log "Updating AWS Secrets Manager with new certificate password"
    
    # Get existing secret
    local existing_secret
    if existing_secret=$(aws secretsmanager get-secret-value \
        --secret-id "$AWS_SECRET_NAME" \
        --region "$AWS_REGION" \
        --query SecretString --output text 2>/dev/null); then
        
        # Update existing secret with new password
        local updated_secret
        updated_secret=$(echo "$existing_secret" | jq --arg p "$password" \
            '. + {($CERT_PASSWORD_KEY): $p}')
        
        echo "$updated_secret" | aws secretsmanager put-secret-value \
            --secret-id "$AWS_SECRET_NAME" \
            --region "$AWS_REGION" \
            --secret-string file:///dev/stdin >/dev/null
    else
        # Create new secret
        local new_secret
        new_secret=$(jq -n --arg p "$password" "{\"$CERT_PASSWORD_KEY\": \$p}")
        
        echo "$new_secret" | aws secretsmanager create-secret \
            --name "$AWS_SECRET_NAME" \
            --region "$AWS_REGION" \
            --secret-string file:///dev/stdin >/dev/null
    fi
    
    log "AWS Secrets Manager updated successfully"
}

# Update Docker secrets
update_docker_secrets() {
    log "Updating Docker secrets"
    
    # Remove existing secrets
    for secret in "${DOCKER_SECRETS[@]}"; do
        if docker secret inspect "$secret" &>/dev/null; then
            log "Removing existing secret: $secret"
            docker secret rm "$secret" || log "Warning: Failed to remove secret $secret"
        fi
    done
    
    # Create new secrets
    for cert_file in "${CERT_FILES[@]}"; do
        local secret_name="${cert_file}"
        local cert_path="$CERT_DIR/$cert_file"
        
        if [[ -f "$cert_path" ]]; then
            log "Creating Docker secret: $secret_name"
            docker secret create "$secret_name" "$cert_path" || fatal "Failed to create secret $secret_name"
        else
            log "Warning: Certificate file not found: $cert_path"
        fi
    done
    
    log "Docker secrets updated successfully"
}

# Restart affected services
restart_services() {
    log "Restarting affected services"
    
    # List of services that use certificates
    local services=("envoy_app" "auth_app" "greeter_app")
    
    for service in "${services[@]}"; do
        if docker service inspect "$service" &>/dev/null; then
            log "Restarting service: $service"
            docker service update --force "$service" || log "Warning: Failed to restart service $service"
        else
            log "Service not found: $service (skipping)"
        fi
    done
    
    log "Service restart completed"
}

# Main certificate management function
manage_certificates() {
    status IN_PROGRESS "checking certificates"
    
    if ! needs_certificate_renewal; then
        log "All certificates are valid, no renewal needed"
        status SUCCESS "certificates valid"
        return 0
    fi
    
    log "Certificate renewal required"
    status IN_PROGRESS "generating certificates"
    
    # Generate new password
    local cert_password
    cert_password=$(random_password)
    
    # Generate certificates
    generate_certificates "$cert_password" "$DOMAIN_NAME"
    
    # Update AWS Secrets Manager
    update_aws_secret "$cert_password"
    
    # Update Docker secrets
    update_docker_secrets
    
    # Restart affected services
    restart_services
    
    status SUCCESS "certificates renewed"
    log "Certificate management completed successfully"
}

# Daemon mode
run_daemon() {
    log "Starting certificate manager daemon"
    
    while true; do
        manage_certificates
        log "Sleeping for 24 hours before next check"
        sleep 86400  # 24 hours
    done
}

###############################################################################
# Main
###############################################################################
main() {
    log "Starting certificate manager"
    
    # Ensure we're running on the lead Docker Swarm manager
    check_swarm_manager
    
    if [[ $DAEMON == true ]]; then
        run_daemon
    else
        manage_certificates
    fi
}

main "$@"
