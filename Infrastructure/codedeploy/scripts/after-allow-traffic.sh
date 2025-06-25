#!/bin/bash

# AfterAllowTraffic hook for CodeDeploy
# This script runs after traffic is allowed to the new version

set -e

# Load environment variables
source /opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/env.sh

echo "Starting AfterAllowTraffic hook for ${SERVICE_NAME}..."

# Clean up old images to save disk space
echo "Cleaning up old images..."
docker image prune -f

# Remove old stack backups (keep last 5)
echo "Cleaning up old stack backups..."
ls -t /tmp/${STACK_NAME}-backup-*.txt 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

# Log successful deployment
echo "Deployment completed successfully!"
echo "Service: ${SERVICE_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Image: ${IMAGE_URI}"
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Optional: Send notification or update monitoring systems
# Example: curl -X POST "https://hooks.slack.com/services/..." -d "payload={\"text\":\"Deployment successful: ${SERVICE_NAME} ${IMAGE_URI}\"}"

echo "AfterAllowTraffic hook completed successfully" 