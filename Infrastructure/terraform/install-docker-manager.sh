#!/bin/bash
set -eux

# Function to log messages with timestamps
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/docker-manager-setup.log
}

# Function to handle errors
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_message "ERROR: Script failed at line $line_number with exit code $exit_code"
    
    # Create a failure indicator file that can be checked by external monitoring
    echo "FAILED: Line $line_number, Exit code $exit_code" > /tmp/docker-manager-setup.status
    exit $exit_code
}

# Set up error handling
trap 'handle_error $LINENO' ERR

log_message "Starting Docker Manager setup..."

# Install Docker
log_message "Installing Docker..."

sudo yum update -y
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to update packages"
    echo "FAILED: Package update failed" > /tmp/docker-manager-setup.status
    exit 1
fi

sudo yum install -y docker
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install Docker"
    echo "FAILED: Docker installation failed" > /tmp/docker-manager-setup.status
    exit 1
fi

sudo service docker start
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to start Docker service"
    echo "FAILED: Docker service start failed" > /tmp/docker-manager-setup.status
    exit 1
fi

sudo usermod -a -G docker ec2-user
log_message "Docker installation completed successfully"

# Initialize swarm as manager
log_message "Initializing Docker Swarm..."

PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to get private IP from metadata service"
    echo "FAILED: Failed to get instance metadata" > /tmp/docker-manager-setup.status
    exit 1
fi

docker swarm init --advertise-addr $PRIVATE_IP
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to initialize Docker Swarm"
    echo "FAILED: Docker Swarm initialization failed" > /tmp/docker-manager-setup.status
    exit 1
fi

log_message "Docker Swarm initialized successfully"

# Get join token and save it
log_message "Generating worker join token..."
WORKER_TOKEN=$(docker swarm join-token worker -q)
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to generate worker join token"
    echo "FAILED: Worker token generation failed" > /tmp/docker-manager-setup.status
    exit 1
fi

echo "Worker join command:"
echo "docker swarm join --token $WORKER_TOKEN $PRIVATE_IP:2377"

# Save token to SSM Parameter for other instance to retrieve
log_message "Storing configuration in SSM Parameter Store..."

aws ssm put-parameter --name "/docker/swarm/worker-token" --value "$WORKER_TOKEN" --type "String" --overwrite
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to store worker token in SSM"
    echo "FAILED: SSM parameter storage failed" > /tmp/docker-manager-setup.status
    exit 1
fi

aws ssm put-parameter --name "/docker/swarm/manager-ip" --value "$PRIVATE_IP" --type "String" --overwrite
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to store manager IP in SSM"
    echo "FAILED: SSM parameter storage failed" > /tmp/docker-manager-setup.status
    exit 1
fi

# Create overlay network
log_message "Creating Docker overlay network..."

docker network create \
  --driver overlay \
  --attachable \
  --subnet 10.20.0.0/16 \
  app-network

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to create overlay network"
    echo "FAILED: Overlay network creation failed" > /tmp/docker-manager-setup.status
    exit 1
fi

# Save network name for worker to reference
aws ssm put-parameter --name "/docker/swarm/network-name" --value "app-network" --type "String" --overwrite
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to store network name in SSM"
    echo "FAILED: SSM parameter storage failed" > /tmp/docker-manager-setup.status
    exit 1
fi

log_message "Docker Manager setup completed successfully!"
echo "SUCCESS: Setup completed successfully" > /tmp/docker-manager-setup.status 