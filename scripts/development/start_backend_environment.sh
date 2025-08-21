#!/bin/bash

working_dir=$(pwd)

# No CLI options currently


# Verify required environment variables
if [ -z "$ASPIRE_BROWSER_TOKEN" ]; then
    print_error "ASPIRE_BROWSER_TOKEN is not set in environment"
    exit 1
fi

# Start Docker Swarm
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    echo "Leaving existing Docker Swarm"
    docker swarm leave --force
fi
echo "Initializing Docker Swarm"
docker swarm init

# Create network
echo "Creating Docker network for swarm called net"
if docker network inspect net &>/dev/null; then
    docker network rm net
fi
docker network create -d overlay --attachable --driver overlay net

# No certificate generation or Docker secrets needed

# Run Aspire Dashboard
echo "Running Aspire Dashboard"
env ASPIRE_BROWSER_TOKEN=$ASPIRE_BROWSER_TOKEN \
    docker stack deploy --compose-file infrastructure/otel-collector/aspire.stack.debug.yaml otel-collector
