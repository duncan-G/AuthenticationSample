#!/usr/bin/env bash
set -euo pipefail

#######################################
# Source utility functions
#######################################
UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../utils" && pwd)"
source "$UTILS_SCRIPT_DIR/print-utils.sh"
source "$UTILS_SCRIPT_DIR/common.sh"

#######################################
# Config
#######################################
working_dir="$(get_project_root)"
PID_DIR="$working_dir/pids"
PID_FILE="$PID_DIR/client.pid"
TERMINAL_PID_FILE="$PID_DIR/client_terminal.pid"
CLIENT_DIR="$working_dir/clients/auth-sample"
GEN_SCRIPT="$working_dir/scripts/development/gen-grpc-web.sh"
STOP_SCRIPT="$working_dir/scripts/stop_client.sh"
ERROR_CODES_SCRIPT="$working_dir/scripts/development/generate_error_codes.js"
DOCKER_TMP_CONTAINER="protoc-gen-grpc-web"

# Protos that should generate NodeJS gRPC clients (not grpc-web)
IGNORE_PROTO_FILES=(
  "$working_dir/microservices/Auth/src/Auth.Grpc/Protos/authz.proto"
)

#######################################
# Setup & cleanup
#######################################
mkdir -p "$PID_DIR"

cleanup() {
  # Best-effort: remove the fixed docker container used by generation
  if docker container rm "$DOCKER_TMP_CONTAINER" >/dev/null 2>&1; then
    print_info "Cleaned up Docker container: $DOCKER_TMP_CONTAINER"
  fi
}
trap cleanup EXIT

#######################################
# Dependency checks
#######################################
if ! command_exists bash; then
  print_error "Missing dependency: bash"
  exit 1
fi

if ! command_exists docker; then
  print_error "Missing dependency: docker"
  exit 1
fi

if ! command_exists find; then
  print_error "Missing dependency: find"
  exit 1
fi

if ! command_exists node; then
  print_error "Missing dependency: node"
  exit 1
fi

if ! command_exists npm; then
  print_error "Missing dependency: npm"
  exit 1
fi

require_directory "$CLIENT_DIR"
require_file "$GEN_SCRIPT"
require_file "$ERROR_CODES_SCRIPT"

#######################################
# Helpers
#######################################
is_in_ignore_proto_list() {
  local file="$1"
  for item in "${IGNORE_PROTO_FILES[@]}"; do
    [[ "$item" == "$file" ]] && return 0
  done
  return 1
}

stop_if_running() {
  if [[ -f "$PID_FILE" ]]; then
    print_warning "Client appears to be running (PID file exists). Stopping existing client..."
    if [[ -x "$STOP_SCRIPT" ]]; then
      bash "$STOP_SCRIPT" || print_warning "Stop script returned non-zero status."
    else
      print_warning "Stop script not found/executable: $STOP_SCRIPT"
    fi
  fi
  rm -f "$PID_FILE" "$TERMINAL_PID_FILE" 2>/dev/null || true
}

start_client_macos() {
  print_info "Starting client (macOS)..."
  # Next.js will automatically load .env.local file
  # Launch a new Terminal tab/window and run the client; save child PID into PID_FILE
  osascript -e "tell application \"Terminal\" to do script \"cd '$CLIENT_DIR' && npm run dev & echo \\$! > '$PID_FILE'; wait\"" >/dev/null
  print_info "Client start command issued. PID will be in $PID_FILE once started."
}

start_client_linux() {
  print_info "Starting client (Linux)..."
  # Prefer gnome-terminal if present; otherwise fallback to nohup in the background
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --title="Auth Sample Client" -- bash -lc "cd '$CLIENT_DIR' && npm run dev & echo \$! > '$PID_FILE'; wait" &
    local term_pid=$!
    echo "$term_pid" > "$TERMINAL_PID_FILE"
    print_info "Client start command issued. Terminal PID: $term_pid"
  else
    print_warning "gnome-terminal not found. Falling back to background mode (nohup)."
    (
      cd "$CLIENT_DIR"
      nohup npm run dev >/dev/null 2>&1 &
      echo $! > "$PID_FILE"
    )
    print_info "Client started in background. PID saved to $PID_FILE"
  fi
}

generate_grpc_services() {
  print_info "Generating grpc-web services for microservices protos..."
  # Find all .proto files under any microservice's Protos directory (excluding internal)
  while IFS= read -r proto_file; do
    if is_in_ignore_proto_list "$proto_file"; then
      print_info "Skipping grpc-web generation for NodeJS proto: $proto_file"
      continue
    fi

    # Determine microservice name from path segment after microservices/
    local rel_path="${proto_file#"$working_dir/microservices/"}"
    local microservice_name="${rel_path%%/*}"
    local microservice_name_lower
    microservice_name_lower="$(tr '[:upper:]' '[:lower:]' <<<"$microservice_name")"

    local output_dir="$CLIENT_DIR/src/lib/services/$microservice_name_lower"
    mkdir -p "$output_dir"

    # Ensure any previous container with the fixed name is removed before each run
    docker container rm "$DOCKER_TMP_CONTAINER" >/dev/null 2>&1 || true

    bash "$GEN_SCRIPT" -i "$proto_file" -o "$output_dir"
  done < <(
    find "$working_dir/microservices" \
      -type f -name "*.proto" \
      -path "*/Protos/*" \
      -not -path "*/Protos/internal/*" \
      | sort
  )
}

generate_error_codes() {
  print_info "Generating error codes..."
  node "$ERROR_CODES_SCRIPT"
}

#######################################
# Main
#######################################
print_header "Starting Auth Sample Client"

stop_if_running
generate_grpc_services
print_success "gRPC services generated successfully"
generate_error_codes
print_success "Error codes generated successfully"
cleanup  # final docker cleanup (no-op if already done)

case "${OSTYPE:-}" in
  darwin*) 
    start_client_macos
    print_success "Client startup initiated for macOS"
    ;;
  linux-gnu*) 
    start_client_linux
    print_success "Client startup initiated for Linux"
    ;;
  *)
    print_warning "Unrecognized OSTYPE ($OSTYPE). Starting client in background as a fallback."
    (
      cd "$CLIENT_DIR"
      nohup npm run dev >/dev/null 2>&1 &
      echo $! > "$PID_FILE"
    )
    print_info "Client started in background. PID saved to $PID_FILE"
    print_success "Client startup completed"
    ;;
esac
