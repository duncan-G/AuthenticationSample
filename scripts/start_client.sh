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

# Load environment variables from .env.docker
if [[ "$container" = true ]]; then
    cd $working_dir/Clients/authentication-sample
    if [ -f .env.docker ]; then
        export $(cat .env.docker | xargs)
    else
        echo "Warning: .env.docker file not found"
    fi
    cd $working_dir
fi

function start_client_macos() {
    echo "Starting client..."
    if [[ "$container" = true ]]; then
        # Start the process and capture its PID
        osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && \
            NEXT_PUBLIC_GREETER_SERVICE_URL=$NEXT_PUBLIC_GREETER_SERVICE_URL npm run dev && echo \\\$PPID > $PID_DIR/client.pid\""
    else
        osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && \
            npm run dev && echo \\\$PPID > $PID_DIR/client.pid\""
    fi
    echo "Client started. PID saved to $PID_DIR/client.pid"
}

function start_client_linux() {
    echo "Starting client..."
    if [[ "$container" = true ]]; then
        # Start gnome-terminal and capture the PID of the npm process
        gnome-terminal -- bash -c "cd $working_dir/Clients/authentication-sample && \
            NEXT_PUBLIC_GREETER_SERVICE_URL=$NEXT_PUBLIC_GREETER_SERVICE_URL npm run dev & \
            echo \$! > $PID_DIR/client.pid; wait"
    else
        gnome-terminal -- bash -c "cd $working_dir/Clients/authentication-sample && \
            npm run dev & \
            echo \$! > $PID_DIR/client.pid; wait"
    fi
    echo "Client started. PID saved to $PID_DIR/client.pid"
}

# Generate Authentication TypeScript services
echo "Generating grpc services"
bash Microservices/.builds/protoc-gen/gen-grpc-web.sh \
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