if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    docker swarm leave --force
fi

# Delete dangling images
docker container prune -f
