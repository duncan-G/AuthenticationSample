#!/usr/bin/env bash
###############################################################################
# certificate-manager.sh – Orchestrates cert‑renewal cycles
#
# • Runs `trigger-certificate-renewal.sh` either once or on a fixed cadence.
# • Logs to STDERR *and* $LOG_FILE (default: /var/log/certificate-manager/…).
# • Gracefully handles errors, exits, and SIGTERM (for systemd / Swarm tasks).
# • Idempotent: daemon loop refuses to overlap runs via `flock`.
#
# -----------------------------------------------------------------------------
# Usage:
#   certificate-manager.sh            # run once
#   certificate-manager.sh -d         # run forever (24 h default)
#   certificate-manager.sh -d -i 3600 # run hourly
#
# Environment overrides:
#   CHECK_INTERVAL   Seconds between runs in daemon mode   (default: 86400)
#   LOG_DIR          Directory for log files               (default: /var/log/certificate-manager)
#   LOG_FILE         Full log file path                    (default: $LOG_DIR/certificate-manager.log)
#   TRIGGER_SCRIPT   Path to renewal script                (default: sibling script)
###############################################################################
set -Eeuo pipefail
shopt -s inherit_errexit nullglob

# ── Defaults ------------------------------------------------------------------
LOG_DIR="${LOG_DIR:-/var/log/certificate-manager}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/certificate-manager.log}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TRIGGER_SCRIPT="${TRIGGER_SCRIPT:-$SCRIPT_DIR/trigger-certificate-renewal.sh}"
CHECK_INTERVAL="${CHECK_INTERVAL:-86400}"   # 24 h
LOCK_FILE="/tmp/certificate-manager.lock"

REQUIRED_BINS=(docker flock)

# ── Logging -------------------------------------------------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()   { printf '[ %s ] %s\n' "$(_ts)" "$*" | tee -a "$LOG_FILE" >&2; }
error() { log "\e[31mERROR:\e[0m $*"; }

# ── Error & signal traps ------------------------------------------------------
DAEMON_MODE=false
cleanup() { log "Shutdown requested – cleaning up"; rm -f "$LOCK_FILE"; }
trap cleanup EXIT
trap 'error "line $LINENO exited with code $?"; [[ $DAEMON_MODE == true ]] || exit 1' ERR
trap 'log "SIGTERM received"; exit 0' TERM INT

# ── CLI parsing ----------------------------------------------------------------
usage() {
  echo "Usage: ${0##*/} [-d] [-i seconds] [-h]"
  echo "  -d, --daemon      Run continuously every \$CHECK_INTERVAL seconds" 
  echo "  -i, --interval    Override interval in seconds (daemon mode only)"
  echo "  -h, --help        Show this help"
}
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--daemon)   DAEMON_MODE=true ; shift ;;
    -i|--interval) CHECK_INTERVAL="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage; exit 1 ;;
  esac
done

# ── Validation ----------------------------------------------------------------
validate(){
  mkdir -p "$LOG_DIR"
  [[ -x $TRIGGER_SCRIPT ]] || { error "Trigger script not executable: $TRIGGER_SCRIPT"; exit 1; }
  [[ $CHECK_INTERVAL =~ ^[0-9]+$ ]] || { error "CHECK_INTERVAL must be integer"; exit 1; }
  for b in "${REQUIRED_BINS[@]}"; do command -v "$b" &>/dev/null || { error "$b missing"; exit 1; }; done
  log "Prerequisites OK (interval: ${CHECK_INTERVAL}s)"
}

# ── Core ----------------------------------------------------------------------
run_trigger(){
  log "▶  Launching renewal trigger"
  if "$TRIGGER_SCRIPT"; then
    log "✅ Trigger finished successfully"
    return 0
  else
    error "Trigger failed"
    return 1
  fi
}

daemon_loop(){
  log "Daemon mode started – running every ${CHECK_INTERVAL}s"
  while true; do
    {
      # Ensure only one cycle at a time even if overlapping containers start
      flock -n 200 || { log "Another cycle is already running"; sleep "$CHECK_INTERVAL"; continue; }
      log "===== Renewal cycle start ====="
      run_trigger || true
      log "===== Cycle end – sleeping ${CHECK_INTERVAL}s ====="
    } 200>"$LOCK_FILE"
    sleep "$CHECK_INTERVAL"
  done
}

# ── Main ----------------------------------------------------------------------
main(){
  log "Certificate‑manager PID $$ started"
  validate
  if $DAEMON_MODE; then
    daemon_loop
  else
    run_trigger
  fi
}

main "$@"
