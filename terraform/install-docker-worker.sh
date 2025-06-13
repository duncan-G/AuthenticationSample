#!/bin/bash
set -eux

# Install Docker
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user


# Wait for manager to be ready and get join token (poll instead of fixed sleep)
echo "Waiting for manager to initialize swarm..."
for i in {1..30}; do
    if aws ssm get-parameter --name "/docker/swarm/worker-token" --query "Parameter.Value" --output text 2>/dev/null; then
        echo "Manager is ready!"
        break
    fi
    echo "Attempt $i/30: Manager not ready yet, waiting 10 seconds..."
    sleep 10
done

# Get join token from SSM Parameter
WORKER_TOKEN=$(aws ssm get-parameter --name "/docker/swarm/worker-token" --query "Parameter.Value" --output text)
MANAGER_IP=$(aws ssm get-parameter --name "/docker/swarm/manager-ip" --query "Parameter.Value" --output text)

# Join the swarm as worker
docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377 