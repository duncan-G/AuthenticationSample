#!/bin/bash

working_dir=$(pwd)

if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    # This will remove all running or dangling containers,
    # networks, configs and secrets in the swarm.
    docker swarm leave --force
fi

docker volume prune -f

bash "$working_dir/scripts/stop_client.sh"