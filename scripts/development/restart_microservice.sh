#!/bin/bash

# Enable strict error handling
set -Eeuo pipefail

working_dir=$(pwd)

usage() {
  echo "Usage: $0 <service-name> [--container] [--stack <stack-name>]"
  echo "Examples:"
  echo "  $0 auth"
  echo "  $0 auth --container --stack auth"
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

service_name="$1"
shift || true

container=false
stack_name="auth"

while [[ ${1:-} ]]; do
  case "$1" in
    --container)
      container=true
      shift
      ;;
    --stack)
      stack_name="${2:-}"
      if [[ -z "$stack_name" ]]; then
        echo "Error: --stack requires a value"
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

LOG_DIR="$working_dir/logs"
PID_DIR="$working_dir/pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

if [[ "$container" == true ]]; then
  # Restart entire stack instead of a single service
  if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
    echo "Error: Docker Swarm is not active. Run './start.sh -b' first."
    exit 1
  fi

  echo "Restarting stack '${stack_name}'"
  docker stack rm "$stack_name" || true

  # Wait for stack and services to be removed
  echo "Waiting for stack removal..."
  for _ in {1..60}; do
    if ! docker stack ls --format '{{.Name}}' | grep -q "^${stack_name}$" && \
       ! docker service ls --format '{{.Name}}' | grep -q "^${stack_name}_"; then
      break
    fi
    sleep 1
  done

  echo "Deploying stack '${stack_name}'"
  env HOME=$HOME docker stack deploy --compose-file microservices/.builds/service.stack.debug.yaml "$stack_name"
  echo ">> Stack restart requested"
  exit 0
else
  # Local restart: perform stop + start directly
  LOG_DIR="$working_dir/logs"
  PID_DIR="$working_dir/pids"
  DOTNET_ENV_VARS="DOTNET_USE_POLLING_FILE_WATCHER=1"

  # POSIX-compatible lookups to avoid associative arrays (macOS default bash)
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

  mkdir -p "$LOG_DIR" "$PID_DIR"

  start_local_service() {
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
      nohup setsid env $DOTNET_ENV_VARS dotnet watch run \
        --project "$csproj_rel" \
        >>"$logfile" 2>&1 &
      echo $! > "$pidfile"
    )
    echo ">> Started $name (PID $(<"$pidfile")) → $logfile"
  }

  stop_local_service() {
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

  if [[ -z "$(service_dir_for "$service_name")" ]]; then
    echo "Error: Unknown service '$service_name'"
    exit 1
  fi

  echo "Restarting local service '$service_name'"
  stop_local_service "$service_name"
  start_local_service "$service_name"
  echo ">> Local restart completed for '$service_name'"
  exit 0
fi


