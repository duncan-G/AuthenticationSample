#!/bin/bash

# AfterInstall hook for CodeDeploy
# This script runs after the new version is installed

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting AfterInstall hook for ${SERVICE_NAME}..."

# Pull the new image
echo "Pulling new image: ${IMAGE_URI}"
docker pull "${IMAGE_URI}"

# Verify image was pulled successfully
if ! docker image inspect "${IMAGE_URI}" >/dev/null 2>&1; then
    echo "ERROR: Failed to pull image ${IMAGE_URI}"
    exit 1
fi

echo "Image pulled successfully: ${IMAGE_URI}"

# Create backup of current stack configuration if it exists
if docker stack ls | grep -q "${STACK_NAME}"; then
    echo "Creating backup of current stack configuration..."
    docker stack ps "${STACK_NAME}" --format "table {{.Name}}\t{{.Image}}\t{{.Node}}" > "/tmp/${STACK_NAME}-backup-$(date +%Y%m%d-%H%M%S).txt"
fi

echo "AfterInstall hook completed successfully" 