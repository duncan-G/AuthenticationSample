#!/bin/bash

container=false
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

# Parse options
while getopts ":c-container" opt; do
  case ${opt} in
    c | container ) 
      container=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -container]"
      exit 1
      ;;
  esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

# Setup environment files for Next.js
function setup_client_env() {
    local client_dir="$working_dir/Clients/authentication-sample"
    local base_env="$client_dir/.env"
    local override_env="$client_dir/.env.dev"
    
    # Start with base environment
    if [ -f "$base_env" ]; then
        echo "Setting up .env.local from base environment..."
        # Filter and copy NEXT_PUBLIC_ variables to .env.local
        grep '^NEXT_PUBLIC_' "$base_env" > "$client_dir/.env.local"
        echo "Base environment variables copied to .env.local"
    else
        echo "Warning: Base environment file $base_env not found"
        # Create empty .env.local file
        touch "$client_dir/.env.local"
    fi
    
    # If container mode, overlay docker environment (overrides base)
    if [[ "$container" = true ]]; then
        if [ -f "$override_env" ]; then
            echo "Applying docker environment overrides..."
            # Create temporary file with docker variables
            local temp_docker="/tmp/docker_env_vars"
            grep '^NEXT_PUBLIC_' "$override_env" > "$temp_docker"
            
            # For each docker variable, replace or add to .env.local
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    local var_name=$(echo "$line" | cut -d'=' -f1)
                    # Remove existing variable if it exists
                    sed -i.bak "/^$var_name=/d" "$client_dir/.env.local"
                    # Add the new variable
                    echo "$line" >> "$client_dir/.env.local"
                fi
            done < "$temp_docker"
            
            # Clean up
            rm -f "$temp_docker" "$client_dir/.env.local.bak"
            echo "Docker environment overrides applied"
        else
            echo "Warning: Docker environment file $override_env not found - using base environment only"
        fi
    fi
    
    echo "Final .env.local created with $(wc -l < "$client_dir/.env.local") variables"
}

function start_client_macos() {
    echo "Starting client..."
    # Next.js will automatically load .env.local file
    osascript -e "tell application \"Terminal\" to do script \"cd '$working_dir/Clients/authentication-sample' && npm run dev & echo \$! > '$PID_FILE'; wait\""
    echo "Client started. PID saved to $PID_DIR/client.pid"
}

function start_client_linux() {
    echo "Starting client..."
    # Next.js will automatically load .env.local file
    # Start gnome-terminal and capture its PID
    gnome-terminal --title="Authentication Sample Client" -- bash -c "cd $working_dir/Clients/authentication-sample && \
        npm run dev & \
        echo \$! > $PID_DIR/client.pid; wait" &
    
    # Save the terminal PID for later cleanup
    TERMINAL_PID=$!
    echo "$TERMINAL_PID" > "$PID_DIR/client_terminal.pid"
    echo "Client started. PID saved to $PID_DIR/client.pid, Terminal PID: $TERMINAL_PID"
}

# Setup environment files
setup_client_env

# Generate Authentication TypeScript services
echo "Generating grpc services"
bash $working_dir/Scripts/development/gen-grpc-web.sh \
    -i $working_dir/Microservices/Authentication/src/Authentication.Grpc/Protos/greet.proto \
    -o $working_dir/Clients/authentication-sample/src/app/services
docker container rm protoc-gen-grpc-web

# Start Next.js application
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    start_client_macos
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    start_client_linux
fi