#!/bin/bash

# BeforeInstall hook for CodeDeploy
# This script runs before the new version is installed

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting BeforeInstall hook for ${SERVICE_NAME}..."

# Log deployment information
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo "Service: ${SERVICE_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Image URI: ${IMAGE_URI}"

# Check if Docker Swarm is active
if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
    echo "ERROR: Docker Swarm is not active"
    exit 1
fi

# Check if required secrets exist
if ! docker secret inspect aspnetapp.pfx >/dev/null 2>&1; then
    echo "ERROR: Required secret 'aspnetapp.pfx' not found"
    exit 1
fi

# Check if overlay network exists
if ! docker network inspect net >/dev/null 2>&1; then
    echo "ERROR: Required overlay network 'net' not found"
    exit 1
fi

echo "BeforeInstall hook completed successfully" 