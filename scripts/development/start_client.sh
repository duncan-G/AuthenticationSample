#!/bin/bash

working_dir=$(pwd)
PID_DIR="$working_dir/pids"
PID_FILE="$PID_DIR/client.pid"

# Create pids directory if it doesn't exist
mkdir -p "$PID_DIR"

# Check if client is already running and stop it
if [ -f "$PID_FILE" ]; then
    echo "Client is already running. Stopping existing client..."
    bash "$working_dir/scripts/stop_client.sh"
fi


# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

function start_client_macos() {
    echo "Starting client..."
    # Next.js will automatically load .env.local file
    osascript -e "tell application \"Terminal\" to do script \"cd '$working_dir/clients/auth-sample' && npm run dev & echo \$! > '$PID_FILE'; wait\""
    echo "Client started. PID saved to $PID_DIR/client.pid"
}

function start_client_linux() {
    echo "Starting client..."
    # Next.js will automatically load .env.local file
    # Start gnome-terminal and capture its PID
    gnome-terminal --title="Auth Sample Client" -- bash -c "cd $working_dir/clients/auth-sample && \
        npm run dev & \
        echo \$! > $PID_DIR/client.pid; wait" &
    
    # Save the terminal PID for later cleanup
    TERMINAL_PID=$!
    echo "$TERMINAL_PID" > "$PID_DIR/client_terminal.pid"
    echo "Client started. PID saved to $PID_DIR/client.pid, Terminal PID: $TERMINAL_PID"
}

# Generate TypeScript services for all microservices' proto files
echo "Generating grpc services for all microservices"

# Find all .proto files under any microservice's Protos directory and generate outputs
while IFS= read -r proto_file; do
    # Determine microservice name from path segment after microservices/
    rel_path=${proto_file#"$working_dir/microservices/"}
    microservice_name=${rel_path%%/*}
    microservice_name_lower=$(echo "$microservice_name" | tr '[:upper:]' '[:lower:]')

    # Output directory includes lowercase microservice name
    output_dir="$working_dir/clients/auth-sample/src/lib/services/$microservice_name_lower"
    mkdir -p "$output_dir"

    # Ensure any previous container with the fixed name is removed before each run
    docker container rm protoc-gen-grpc-web >/dev/null 2>&1 || true

    bash "$working_dir/scripts/development/gen-grpc-web.sh" \
        -i "$proto_file" \
        -o "$output_dir"
done < <(find "$working_dir/microservices" -type f -name "*.proto" -path "*/Protos/*" -not -path "*/Protos/internal/*" | sort)

node "$working_dir/scripts/development/generate_error_codes.js"

# Final cleanup (no-op if already removed)
docker container rm protoc-gen-grpc-web >/dev/null 2>&1 || true

# Start Next.js application
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    start_client_macos
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    start_client_linux
fi