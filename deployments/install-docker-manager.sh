#!/bin/bash
set -eux

# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# Initialize swarm as manager
PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
docker swarm init --advertise-addr $PRIVATE_IP

# Get join token and save it
WORKER_TOKEN=$(docker swarm join-token worker -q)
echo "Worker join command:"
echo "docker swarm join --token $WORKER_TOKEN $PRIVATE_IP:2377"

# Save token to SSM Parameter for other instance to retrieve
aws ssm put-parameter --name "/docker/swarm/worker-token" --value "$WORKER_TOKEN" --type "String" --overwrite
aws ssm put-parameter --name "/docker/swarm/manager-ip" --value "$PRIVATE_IP" --type "String" --overwrite

# Create overlay network
echo "Creating Docker overlay network..."
docker network create \
  --driver overlay \
  --attachable \
  --subnet 10.20.0.0/16 \
  app-network

# Save network name for worker to reference
aws ssm put-parameter --name "/docker/swarm/network-name" --value "app-network" --type "String" --overwrite 