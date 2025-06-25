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
LOG_DIR="$working_dir/logs"
PID_DIR="$working_dir/pids"
DOTNET_ENV_VARS="DOTNET_USE_POLLING_FILE_WATCHER=1"

containerize_microservices=false

# Parse options
while getopts ":c-containerize" opt; do
  case ${opt} in
    c | containerize ) 
      containerize_microservices=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -containerize]"
      exit 1
      ;;
  esac
done

# Create necessary directories
mkdir -p "$LOG_DIR" "$PID_DIR"

# Clear existing logs to start fresh
echo "Clearing existing logs..."
rm -f "$LOG_DIR"/*.log

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

# Set up trap for cleanup only when not containerized
if [ "$containerize_microservices" = false ]; then
    trap cleanup INT TERM EXIT
fi

# Start Postgres
bash $working_dir/scripts/start_database.sh

# Deploy Authentication microservice if containerization is enabled
if [ "$containerize_microservices" = true ]; then
    # Check if Docker Swarm is active
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
        echo "Error: Docker Swarm is not active. Please run './start.sh -b' first to initialize the environment"
        exit 1
    fi

    # Start proxy
    bash $working_dir/scripts/start_proxy.sh

    # Build Authentication and deploy to swarm
    image_name="authentication-sample/authentication"
    echo "Building Authentication service"
    cd $working_dir/Microservices/Authentication
    env ContainerRepository=$image_name \
      dotnet publish --os linux --arch x64 /t:PublishContainer
    cd ../..

    echo "Deploying Authentication service to swarm"
    env IMAGE_NAME=$image_name \
        CERTIFICATE_PASSWORD=$CERTIFICATE_PASSWORD \
        ENV_FILE=$working_dir/Microservices/Authentication/src/Authentication.Grpc/.env \
        OVERRIDE_ENV_FILE=$working_dir/Microservices/Authentication/src/Authentication.Grpc/.env.docker \
        docker stack deploy --compose-file Microservices/.builds/service.stack.debug.yaml authentication
    
else
    # Start Authentication service with proper logging and process management
    echo "Starting Authentication service"
    service_name="authentication"
    logfile="$LOG_DIR/$service_name.log"
    pidfile="$PID_DIR/$service_name.pid"

    (
        cd "$working_dir/Microservices/Authentication"
        nohup env $DOTNET_ENV_VARS setsid dotnet watch run \
            --project src/Authentication.Grpc/Authentication.Grpc.csproj \
            >>"$logfile" 2>&1 &
        echo $! > "$pidfile"
    )

    echo ">> Started $service_name (PID $(<"$pidfile")) → $logfile"
    echo -e "\n>> Service is up. Press Ctrl-C to stop.\n"

    # Keep the script running to maintain the trap
    while true; do
        sleep 1
        # Check if the service is still running
        if ! kill -0 "$(<"$pidfile")" 2>/dev/null; then
            echo "Service stopped unexpectedly. Check logs at $logfile"
            exit 1
        fi
    done
fi
