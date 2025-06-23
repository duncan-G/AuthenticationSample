#!/bin/bash

# BeforeAllowTraffic hook for CodeDeploy
# This script runs before traffic is allowed to the new version

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting BeforeAllowTraffic hook for ${SERVICE_NAME}..."

# Perform final validation before allowing traffic
echo "Performing final validation..."

# Check if service is responding
echo "Checking service responsiveness..."
RESPONSE_CHECK_ATTEMPTS=5
RESPONSE_CHECK_ATTEMPT=0

while [ $RESPONSE_CHECK_ATTEMPT -lt $RESPONSE_CHECK_ATTEMPTS ]; do
    if curl -f -s --connect-timeout 5 "https://localhost:10000/health" >/dev/null 2>&1; then
        echo "Service is responding to health checks"
        break
    fi
    
    RESPONSE_CHECK_ATTEMPT=$((RESPONSE_CHECK_ATTEMPT + 1))
    echo "Response check attempt $RESPONSE_CHECK_ATTEMPT/$RESPONSE_CHECK_ATTEMPTS failed, retrying..."
    sleep 2
done

if [ $RESPONSE_CHECK_ATTEMPT -eq $RESPONSE_CHECK_ATTEMPTS ]; then
    echo "ERROR: Service is not responding to health checks"
    echo "Service logs:"
    docker service logs "${STACK_NAME}_app" --tail 10 || true
    exit 1
fi

# Check resource usage
echo "Checking resource usage..."
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep "${STACK_NAME}" || true

# Log deployment success
echo "Deployment validation completed successfully"
echo "Service ${SERVICE_NAME} is ready to receive traffic"

echo "BeforeAllowTraffic hook completed successfully" 