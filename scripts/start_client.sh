#!/bin/bash

container=false
working_dir=$(pwd)

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
        osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && \
            NEXT_PUBLIC_GREETER_SERVICE_URL=$NEXT_PUBLIC_GREETER_SERVICE_URL npm run dev \""
    else
        osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && npm run dev \""
    fi
}

function start_client_linux() {
    echo "Starting client..."
    if [[ "$container" = true ]]; then
        gnome-terminal -- bash -c "cd $working_dir/Clients/authentication-sample && \
            NEXT_PUBLIC_GREETER_SERVICE_URL=$NEXT_PUBLIC_GREETER_SERVICE_URL npm run dev; exec bash"
    else
        gnome-terminal -- bash -c "cd $working_dir/Clients/authentication-sample && npm run dev; exec bash"
    fi
}

# Generate Authentication TypeScript services
echo "Generating grpc services"
bash Microservices/.builds/protoc-gen/gen-grpc-web.sh \
    -i $working_dir/Microservices/Authentication/src/Authentication.Grpc/Protos/greet.proto \
    -o $working_dir/Clients/authentication-sample/src/app/services
docker container rm protoc-gen-grpc-web

# Start Next.js application
echo "Starting client..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    start_client_macos
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    start_client_linux
fi