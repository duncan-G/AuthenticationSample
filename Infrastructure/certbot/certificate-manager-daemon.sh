#!/usr/bin/env bash
# certificate-manager-daemon.sh - Daemon wrapper for certificate management
# Runs trigger-certificate-renewal.sh at regular intervals

set -Eeuo pipefail
shopt -s inherit_errexit

readonly LOG_FILE="/var/log/certificate-secret-manager.log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TRIGGER_SCRIPT="$SCRIPT_DIR/trigger-certificate-renewal.sh"

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
  
  # Check if trigger script exists and is executable
  if [[ ! -f "$TRIGGER_SCRIPT" ]]; then
    log "ERROR: trigger-certificate-renewal.sh not found at $TRIGGER_SCRIPT"
    exit 1
  fi
  
  if [[ ! -x "$TRIGGER_SCRIPT" ]]; then
    log "ERROR: trigger-certificate-renewal.sh is not executable"
    exit 1
  fi
  
  # Check required binaries
  for bin in docker; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      log "ERROR: required binary '$bin' not found in PATH"
      exit 1
    fi
  done
  
  log "Prerequisites validated successfully"
}

# Run certificate renewal trigger
run_certificate_renewal() {
  log "Running certificate renewal trigger"
  
  if "$TRIGGER_SCRIPT"; then
    log "Certificate renewal trigger completed successfully"
    return 0
  else
    log "ERROR: Certificate renewal trigger failed"
    return 1
  fi
}

# Daemon mode - run continuously
run_daemon() {
  log "Starting certificate renewal daemon"
  log "Check interval: ${CHECK_INTERVAL}s ($(($CHECK_INTERVAL / 3600)) hours)"
  
  while true; do
    log "=== Certificate renewal cycle started ==="
    
    if run_certificate_renewal; then
      log "Certificate renewal cycle completed successfully"
    else
      log "Certificate renewal cycle failed, will retry on next cycle"
    fi
    
    log "Sleeping for ${CHECK_INTERVAL}s until next check"
    sleep "$CHECK_INTERVAL"
  done
}

# Single run mode
run_once() {
  log "Running certificate renewal once"
  run_certificate_renewal
}

# Main function
main() {
  log "Certificate renewal daemon started"
  
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