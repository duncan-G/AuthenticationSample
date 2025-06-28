#!/usr/bin/env bash
# manage_certificate_secrets.sh - Daemon wrapper for certificate management
# Runs certificate-manager.sh at regular intervals

set -Eeuo pipefail
shopt -s inherit_errexit

readonly LOG_FILE="/var/log/certificate-secret-manager.log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CERT_MANAGER_SCRIPT="$SCRIPT_DIR/certificate-manager.sh"

# Default configuration - check every 24 hours
readonly CHECK_INTERVAL="${CHECK_INTERVAL:-86400}"  # 24 hours in seconds
readonly DAEMON_MODE="${DAEMON_MODE:-false}"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2
}

on_error() {
  local ec=$? line=$1
  log "ERROR: line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR

# Check if running as daemon
is_daemon_mode() {
  [[ "$1" == "--daemon" ]]
}

# Validate prerequisites
validate_prerequisites() {
  log "Validating prerequisites"
  
  # Check if certificate-manager.sh exists and is executable
  if [[ ! -f "$CERT_MANAGER_SCRIPT" ]]; then
    log "ERROR: certificate-manager.sh not found at $CERT_MANAGER_SCRIPT"
    exit 1
  fi
  
  if [[ ! -x "$CERT_MANAGER_SCRIPT" ]]; then
    log "ERROR: certificate-manager.sh is not executable"
    exit 1
  fi
  
  # Check required binaries
  for bin in jq aws openssl certbot; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      log "ERROR: required binary '$bin' not found in PATH"
      exit 1
    fi
  done
  
  log "Prerequisites validated successfully"
}

# Run certificate management
run_certificate_management() {
  log "Running certificate management"
  
  if "$CERT_MANAGER_SCRIPT"; then
    log "Certificate management completed successfully"
    return 0
  else
    log "ERROR: Certificate management failed"
    return 1
  fi
}

# Daemon mode - run continuously
run_daemon() {
  log "Starting certificate secret manager daemon"
  log "Check interval: ${CHECK_INTERVAL}s ($(($CHECK_INTERVAL / 3600)) hours)"
  
  while true; do
    log "=== Certificate check cycle started ==="
    
    if run_certificate_management; then
      log "Certificate check completed successfully"
    else
      log "Certificate check failed, will retry on next cycle"
    fi
    
    log "Sleeping for ${CHECK_INTERVAL}s until next check"
    sleep "$CHECK_INTERVAL"
  done
}

# Single run mode
run_once() {
  log "Running certificate management once"
  run_certificate_management
}

# Main function
main() {
  log "Certificate secret manager started"
  
  # Validate prerequisites
  validate_prerequisites
  
  # Determine run mode
  if is_daemon_mode "$1"; then
    run_daemon
  else
    run_once
  fi
}

# Run main function with all arguments
main "$@" 