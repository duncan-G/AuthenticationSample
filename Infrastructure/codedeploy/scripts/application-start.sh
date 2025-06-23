#!/bin/bash

# ApplicationStart hook for CodeDeploy
# This script starts the new version of the application

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting ApplicationStart hook for ${SERVICE_NAME}..."

# Set environment variables for deployment
export IMAGE_NAME="${IMAGE_URI}"
export CERTIFICATE_PASSWORD="${CERTIFICATE_PASSWORD}"
export ENV_FILE="/opt/microservices/${SERVICE_NAME}/.env"
export OVERRIDE_ENV_FILE="/opt/microservices/${SERVICE_NAME}/.env.docker"

# Create temporary stack file with new image
cat > /tmp/${STACK_NAME}-stack.yml << EOF
version: "3.8"

services:
  app:
    image: ${IMAGE_URI}
    env_file:
      - ${ENV_FILE}
      - ${OVERRIDE_ENV_FILE}
    environment:
      ASPNETCORE_URLS: https://+:8000
      ASPNETCORE_ENVIRONMENT: Production
    networks:
      - net
    secrets:
      - source: aspnetapp.pfx
        target: /https/aspnetapp.pfx
    deploy:
      mode: global
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 3
        window: 120s
      update_config:
        parallelism: 1
        delay: 10s
        failure_action: rollback
        monitor: 15s
        order: stop-first
networks:
  net:
    external: true

secrets:
  aspnetapp.pfx:
    external: true
EOF

# Deploy or update the stack
echo "Deploying ${SERVICE_NAME} to Docker Swarm..."
if docker stack ls | grep -q "${STACK_NAME}"; then
    echo "Updating existing stack: ${STACK_NAME}"
    docker stack deploy --compose-file /tmp/${STACK_NAME}-stack.yml "${STACK_NAME}"
else
    echo "Creating new stack: ${STACK_NAME}"
    docker stack deploy --compose-file /tmp/${STACK_NAME}-stack.yml "${STACK_NAME}"
fi

# Wait for deployment to start
echo "Waiting for deployment to start..."
sleep 10

# Check if deployment is progressing
if ! docker stack ps "${STACK_NAME}" --format "table {{.Name}}\t{{.CurrentState}}" | grep -q "Running\|Pending"; then
    echo "ERROR: Deployment failed to start properly"
    docker stack ps "${STACK_NAME}"
    exit 1
fi

echo "ApplicationStart hook completed successfully" 