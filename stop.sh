#!/bin/bash

if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    docker swarm leave --force
fi

# Delete dangling resources
docker container prune -f
docker image prune -f
docker volume prune -f
docker network prune -f