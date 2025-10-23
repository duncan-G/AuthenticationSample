#!/bin/bash

working_dir=$(pwd)
PID_DIR="$working_dir/pids"
PID_FILE="$PID_DIR/client.pid"
TERMINAL_PID_FILE="$PID_DIR/client_terminal.pid"
CLIENT_DIR="$working_dir/clients/auth-sample"

echo "Stopping client..."

function close_terminal_window() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - close terminal windows running in auth-sample directory
        echo "Attempting to close terminal window on macOS..."
        osascript -e 'tell application "Terminal" to close (every window whose name contains "auth-sample")' 2>/dev/null || true
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - try to close gnome-terminal window
        echo "Attempting to close terminal window on Linux..."
        if [ -f "$TERMINAL_PID_FILE" ]; then
            TERMINAL_PID=$(cat "$TERMINAL_PID_FILE")
            if kill -0 "$TERMINAL_PID" 2>/dev/null; then
                kill "$TERMINAL_PID" 2>/dev/null
                echo "Terminal window closed."
            fi
            rm -f "$TERMINAL_PID_FILE"
        fi
    fi
}

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping client process (PID: $PID)..."
        
        # Try graceful shutdown first
        kill -TERM "$PID"
        
        # Wait up to 5 seconds for graceful shutdown
        for i in {1..5}; do
            if ! kill -0 "$PID" 2>/dev/null; then
                echo "Client stopped gracefully."
                close_terminal_window
                rm -f "$PID_FILE"
                exit 0
            fi
            sleep 1
        done
        
        # Force kill if still running
        echo "Force killing client process..."
        kill -9 "$PID" 2>/dev/null
        echo "Client force stopped."
        close_terminal_window
    else
        echo "Client process (PID: $PID) is not running."
        close_terminal_window
    fi
    
    rm -f "$PID_FILE"
else
    echo "No client PID file found at $PID_FILE"
    close_terminal_window
    echo "Attempted to close any open client terminal windows."
fi 
