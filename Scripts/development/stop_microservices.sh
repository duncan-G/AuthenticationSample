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

        if kill -0 "$pid" 2>/dev/null; then
            echo "  • Stopping $name (PID $pid)"

            # 1) Try to SIGINT the entire process group (requires 'setsid' at startup)
            if kill -0 "-$pid" 2>/dev/null; then
                kill -INT -- "-$pid"
            else
                # fallback: SIGINT watcher, then its children
                kill -INT "$pid"
                pkill -INT -P "$pid"
            fi

            # 2) Wait up to 5s for it to die gracefully
            for _ in {1..5}; do
                sleep 1
                kill -0 "$pid" 2>/dev/null || break
            done

            # 3) If still alive, force-kill group or individual
            if kill -0 "$pid" 2>/dev/null; then
                if kill -0 "-$pid" 2>/dev/null; then
                    kill -9 -- "-$pid"
                else
                    pkill -9 -P "$pid"
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
        fi

        rm -f "$pidfile"
    done

    echo ">> All services stopped."
}

# Run cleanup
cleanup 