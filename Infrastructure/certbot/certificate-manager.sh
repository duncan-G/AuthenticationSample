#!/usr/bin/env bash
###############################################################################
# certificate-manager.sh
#
# Fires `trigger-certificate-renewal.sh` either once or at a fixed interval
# (daemon mode).  Logs go to STDERR *and* `/var/log/certificate-secret-manager.log`.
#
# ---------------------------------------------------------------------------
# Usage:
#   certificate-manager.sh           # run once
#   certificate-manager.sh --daemon  # run forever (default interval 24 h)
#   certificate-manager.sh --help
#
# Environment overrides:
#   CHECK_INTERVAL  Seconds between runs in daemon mode   (default: 86400 s)
#   LOG_FILE        Log file path                         (default: see below)
#   TRIGGER_SCRIPT  Path to renewal script                (default: sibling)
###############################################################################

set -Eeuo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
readonly LOG_FILE="${LOG_FILE:-/var/log/certificate-secret-manager.log}"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TRIGGER_SCRIPT="${TRIGGER_SCRIPT:-${SCRIPT_DIR}/trigger-certificate-renewal.sh}"
readonly CHECK_INTERVAL="${CHECK_INTERVAL:-86400}"   # 24 h
readonly REQUIRED_BINS=(docker)

# ── Logging helpers ─────────────────────────────────────────────────────────
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() { printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2; }

die() { log "ERROR: $*"; exit 1; }

# Error trap that can be customized based on mode
error_trap() { 
  log "ERROR: Line $LINENO exited with status $?"
  if [[ "${DAEMON_MODE:-false}" == "true" ]]; then
    log "Daemon mode: continuing despite error"
  else
    exit 1
  fi
}

trap error_trap ERR

# ── CLI parsing ─────────────────────────────────────────────────────────────
show_help() {
  printf 'Usage: %s [--daemon] [--help]\n\n' "${0##*/}"
  printf '  --daemon, -d   Run continuously every %s seconds\n' "$CHECK_INTERVAL"
  printf '  --help,   -h   Show this help\n'
}

DAEMON_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--daemon) DAEMON_MODE=true ;;
    -h|--help)   show_help; exit 0 ;;
    *)           die "Unknown argument: $1" ;;
  esac
  shift
done

# ── Validation ──────────────────────────────────────────────────────────────
validate() {
  log "Validating prerequisites"

  [[ -x "$TRIGGER_SCRIPT" ]] \
    || die "Trigger script not found or not executable: $TRIGGER_SCRIPT"

  for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" &>/dev/null || die "Required binary not found: $bin"
  done

  [[ "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] \
    || die "CHECK_INTERVAL must be an integer (seconds)"

  log "Prerequisites OK"
}

# ── Core actions ────────────────────────────────────────────────────────────
run_trigger() {
  log "Running certificate renewal trigger"
  if "$TRIGGER_SCRIPT"; then
    log "Trigger completed successfully"
    return 0
  else
    log "Trigger failed"
    return 1
  fi
}

daemon_loop() {
  log "Daemon mode; interval: ${CHECK_INTERVAL}s (~$((CHECK_INTERVAL/3600)) h)"
  while true; do
    log "===== Renewal cycle start ====="
    if (run_trigger); then
      log "Renewal cycle OK"
    else
      log "Renewal cycle failed; will retry"
    fi
    log "Sleeping ${CHECK_INTERVAL}s"
    sleep "$CHECK_INTERVAL"
  done
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  log "Certificate manager started (PID $$)"
  validate
  if $DAEMON_MODE; then
    daemon_loop
  else
    run_trigger
  fi
}

main

