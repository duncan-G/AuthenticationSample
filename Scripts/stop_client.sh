#!/bin/bash

working_dir=$(pwd)
PID_DIR="$working_dir/pids"
PID_FILE="$PID_DIR/client.pid"

echo "Stopping client..."

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
                rm -f "$PID_FILE"
                exit 0
            fi
            sleep 1
        done
        
        # Force kill if still running
        echo "Force killing client process..."
        kill -9 "$PID" 2>/dev/null
        echo "Client force stopped."
    else
        echo "Client process (PID: $PID) is not running."
    fi
    
    rm -f "$PID_FILE"
else
    echo "No client PID file found at $PID_FILE"
    echo "You may need to manually close the client terminal window."
fi 