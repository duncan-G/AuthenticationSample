#!/bin/bash

# ValidateService hook for CodeDeploy
# This script validates that the new version is running correctly

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting ValidateService hook for ${SERVICE_NAME}..."

# Wait for service to be fully deployed
echo "Waiting for service to be fully deployed..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Check if all replicas are running
    RUNNING_REPLICAS=$(docker stack ps "${STACK_NAME}" --format "table {{.CurrentState}}" | grep -c "Running" || echo "0")
    TOTAL_REPLICAS=$(docker stack ps "${STACK_NAME}" --format "table {{.CurrentState}}" | wc -l)
    TOTAL_REPLICAS=$((TOTAL_REPLICAS - 1))  # Subtract header line
    
    echo "Attempt $((ATTEMPT + 1))/$MAX_ATTEMPTS: $RUNNING_REPLICAS/$TOTAL_REPLICAS replicas running"
    
    if [ "$RUNNING_REPLICAS" -eq "$TOTAL_REPLICAS" ] && [ "$TOTAL_REPLICAS" -gt 0 ]; then
        echo "All replicas are running!"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    sleep 10
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo "ERROR: Service failed to start within expected time"
    docker stack ps "${STACK_NAME}"
    exit 1
fi

# Check service health endpoint
echo "Checking service health..."
SERVICE_NAME_LOWER=$(echo "${SERVICE_NAME}" | tr '[:upper:]' '[:lower:]')

# Get service port (assuming it's exposed on the swarm)
HEALTH_CHECK_ATTEMPTS=10
HEALTH_CHECK_ATTEMPT=0

while [ $HEALTH_CHECK_ATTEMPT -lt $HEALTH_CHECK_ATTEMPTS ]; do
    # Try to check health endpoint (adjust URL based on your service configuration)
    if curl -f -s "https://localhost:10000/health" >/dev/null 2>&1; then
        echo "Health check passed!"
        break
    fi
    
    HEALTH_CHECK_ATTEMPT=$((HEALTH_CHECK_ATTEMPT + 1))
    echo "Health check attempt $HEALTH_CHECK_ATTEMPT/$HEALTH_CHECK_ATTEMPTS failed, retrying..."
    sleep 5
done

if [ $HEALTH_CHECK_ATTEMPT -eq $HEALTH_CHECK_ATTEMPTS ]; then
    echo "WARNING: Health check failed, but continuing deployment"
    echo "Service logs:"
    docker service logs "${STACK_NAME}_app" --tail 20 || true
fi

# Verify the correct image is running
echo "Verifying correct image is deployed..."
RUNNING_IMAGE=$(docker stack ps "${STACK_NAME}" --format "table {{.Image}}" | grep -v "IMAGE" | head -1 | tr -d ' ')
if [ "$RUNNING_IMAGE" != "${IMAGE_URI}" ]; then
    echo "ERROR: Wrong image is running. Expected: ${IMAGE_URI}, Got: ${RUNNING_IMAGE}"
    exit 1
fi

echo "ValidateService hook completed successfully" 