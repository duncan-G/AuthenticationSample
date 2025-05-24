#!/bin/bash

working_dir=$(pwd)

containerize_microservices=false

# Parse options
while getopts ":c-containerize_microservices" opt; do
  case ${opt} in
    c | containerize_microservices ) 
      containerize_microservices=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -containerize_microservices]"
      exit 1
      ;;
  esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

# Start Docker Swarm
echo "Starting Docker Swarm"
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    docker swarm leave --force
fi
docker swarm init

# Create network
echo "Creating Docker network for Swarm called net"
docker network prune -f
if docker network inspect net &>/dev/null; then
    docker network rm net
fi
docker network create -d overlay --attachable --driver overlay net

# Run Aspire Dashboard
docker stack deploy --compose-file Microservices/.builds/aspire/aspire.stack.debug.yaml aspire

# Run Postgres
bash start_database.sh -r

# Generate Authentication grpc services
bash Microservices/.builds/protoc-gen/gen-grpc-web.sh \
    -i $working_dir/Microservices/Authentication/src/Authentication.Grpc/Protos/greet.proto \
    -o $working_dir/Clients/authentication-sample/src/app/services

# Start Next.js application
echo "Starting Authentication client..."
osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && npm run dev --experimental-https \""
cd $working_dir

echo "Authentication client started in a new terminal window"
