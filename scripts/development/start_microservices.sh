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

# Service registry (extend as more microservices are added)
SERVICES=(
  auth
  greeter
)

declare -A SERVICE_DIRS=(
    [auth]="Auth"
    [greeter]="Greeter")
declare -A SERVICE_CSPROJ=(
    [auth]="src/Auth.Grpc/Auth.Grpc.csproj"
    [greeter]="Greeter/Greeter.csproj"
)

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

# Clear existing logs to start fresh
mkdir -p "$LOG_DIR" "$PID_DIR"
echo "Clearing existing logs..."
rm -f "$LOG_DIR"/*.log

# Deploy Auth microservice if containerization is enabled
if [ "$containerize_microservices" = true ]; then
    # Check if Docker Swarm is active
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
        echo "Error: Docker Swarm is not active. Please run './start.sh -b' first to initialize the environment"
        exit 1
    fi

    confirmed_users_count="$("$working_dir"/scripts/development/get_confirmed_user_count.sh)" || exit 1

    # Build service images (extend mapping as needed)
    # Current image mapping
    declare -A SERVICE_IMAGES=(
        [auth]="auth-sample/auth"
        [greeter]="auth-sample/greeter"
    )

    for service_name in "${SERVICES[@]}"; do
        image_name="${SERVICE_IMAGES[$service_name]}"
        if [[ -z "${image_name:-}" ]]; then
            echo "Warning: No image mapping for $service_name; skipping build"
            continue
        fi
        echo "Building $service_name service"
        cd "$working_dir/microservices/${SERVICE_DIRS[$service_name]}"
        env ContainerRepository="$image_name" \
          dotnet publish --os linux --arch x64 /t:PublishContainer
        cd - >/dev/null

        echo "Deploying services to swarm"
        env IMAGE_NAME=$image_name \
            HOME=$HOME \
            COGNITO_CONFIRMED_USERS_COUNT=${confirmed_users_count} \
            AWS_PROFILE=$AWS_PROFILE \
            AWS_REGION=$AWS_REGION \
            docker stack deploy --compose-file microservices/.builds/service.stack.debug.yaml $service_name
    done
    
else
    # Generic helpers for multiple services
    start_service() {
        local name="$1"
        local logfile="$LOG_DIR/$name.log"
        local pidfile="$PID_DIR/$name.pid"
        local service_dir="${SERVICE_DIRS[$name]:-}"
        local csproj_rel="${SERVICE_CSPROJ[$name]:-}"

        if [[ -z "${service_dir:-}" || -z "${csproj_rel:-}" ]]; then
            echo "Error: Unknown service '$name'"
            return 1
        fi

        echo "Starting $name service"
        (
            cd "$working_dir/microservices/$service_dir"
            nohup setsid env $DOTNET_ENV_VARS dotnet watch run \
                --project "$csproj_rel" \
                >>"$logfile" 2>&1 &
            echo $! > "$pidfile"
        )
        echo ">> Started $name (PID $(<"$pidfile")) → $logfile"
    }

    stop_service() {
        local name="$1"
        local pidfile="$PID_DIR/$name.pid"
        if [[ -f "$pidfile" ]]; then
            local pid
            pid=$(<"$pidfile")
            if kill -0 "-$pid" 2>/dev/null || kill -0 "$pid" 2>/dev/null; then
                echo "Stopping $name (PID/PGID $pid)"
                if kill -0 "-$pid" 2>/dev/null; then
                    kill -INT -- "-$pid" || true
                else
                    kill -INT "$pid" 2>/dev/null || true
                    pkill -INT -P "$pid" 2>/dev/null || true
                fi
                for _ in {1..5}; do
                    sleep 1
                    if ! kill -0 "-$pid" 2>/dev/null && ! kill -0 "$pid" 2>/dev/null; then
                        break
                    fi
                done
                if kill -0 "-$pid" 2>/dev/null; then
                    kill -9 -- "-$pid" || true
                elif kill -0 "$pid" 2>/dev/null; then
                    pkill -9 -P "$pid" 2>/dev/null || true
                    kill -9 "$pid" 2>/dev/null || true
                fi
            fi
            rm -f "$pidfile"
        fi
    }

    restart_service() {
        local name="$1"
        echo "Restarting $name service"
        stop_service "$name"
        start_service "$name"
    }

    # Launch all registered services
    for service_name in "${SERVICES[@]}"; do
        start_service "$service_name"
    done
fi
