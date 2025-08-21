#!/bin/bash

# Enable strict error handling and safer script execution:
# -E: ERR trap is inherited by shell functions, command substitutions, and subshells
# -e: Exit immediately if any command returns non-zero status (fails)
# -u: Treat unset variables as an error and exit immediately
# -o pipefail: Pipeline exit status is the last command that failed, or zero if all succeed
# This helps catch common programming errors and prevents silent failures
set -Eeuo pipefail

working_dir=$(pwd)

# Configuration
PID_DIR="$working_dir/pids"

# Cleanup function to handle service shutdown
cleanup() {
    echo -e "\n>> Shutting down services..."
    for pidfile in "$PID_DIR"/*.pid; do
        [[ -e $pidfile ]] || continue
        
        # Skip client.pid files - they are managed separately
        if [[ $(basename "$pidfile") == "client.pid" ]]; then
            continue
        fi

        pid=$(<"$pidfile")
        name=$(basename "$pidfile" .pid)

        # Prefer checking the process group first so we still catch children if leader died
        if kill -0 "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
            echo "  • Stopping $name (PID/PGID $pid)"

            # 1) Try to SIGINT the entire process group (requires 'setsid' at startup)
            if kill -0 "-$pid" 2>/dev/null; then
                kill -INT -- "-$pid"
            else
                # fallback: SIGINT watcher, then its children
                kill -INT "$pid" 2>/dev/null || true
                pkill -INT -P "$pid" 2>/dev/null || true
            fi

            # 2) Wait up to 5s for it to die gracefully
            for _ in {1..5}; do
                sleep 1
                if ! kill -0 "-$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
                    break
                fi
            done

            # 3) If still alive, force-kill group or individual
            if kill -0 "-$pid" 2>/dev/null; then
                kill -9 -- "-$pid"
            elif kill -0 "$pid" 2>/dev/null; then
                pkill -9 -P "$pid" 2>/dev/null || true
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi

        rm -f "$pidfile"
    done

    echo ">> All services stopped."
}

# Run cleanup
cleanup 