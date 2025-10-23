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

# POSIX-compatible lookups to avoid bash associative arrays on macOS's older bash
service_dir_for() {
  case "$1" in
    auth) echo "Auth" ;;
    greeter) echo "Greeter" ;;
    *) echo "" ;;
  esac
}

service_csproj_for() {
  case "$1" in
    auth) echo "src/Auth.Grpc/Auth.Grpc.csproj" ;;
    greeter) echo "Greeter/Greeter.csproj" ;;
    *) echo "" ;;
  esac
}

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
    service_image_for() {
        case "$1" in
            auth) echo "auth-sample/auth" ;;
            greeter) echo "auth-sample/greeter" ;;
            *) echo "" ;;
        esac
    }

    for service_name in "${SERVICES[@]}"; do
        image_name="$(service_image_for "$service_name")"
        if [[ -z "${image_name:-}" ]]; then
            echo "Warning: No image mapping for $service_name; skipping build"
            continue
        fi
        echo "Building $service_name service"
        cd "$working_dir/microservices/$(service_dir_for "$service_name")"
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
        local service_dir="$(service_dir_for "$name")"
        local csproj_rel="$(service_csproj_for "$name")"

        if [[ -z "${service_dir:-}" || -z "${csproj_rel:-}" ]]; then
            echo "Error: Unknown service '$name'"
            return 1
        fi

        echo "Starting $name service"
        (
            cd "$working_dir/microservices/$service_dir"
            echo "current directory: $(pwd)"
            echo "csproj_rel: $csproj_rel"
            nohup setsid env $DOTNET_ENV_VARS dotnet watch run \
                --project "$csproj_rel" \
                >>"$logfile" 2>&1 &
            echo $! > "$pidfile"
        )
        echo ">> Started $name (PID $(<"$pidfile")) → $logfile"
    }

    # Launch all registered services
    for service_name in "${SERVICES[@]}"; do
        start_service "$service_name"
        sleep 5
    done
fi
