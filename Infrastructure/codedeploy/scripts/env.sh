#!/bin/bash

# Environment variables for CodeDeploy deployment
# This file is sourced by all deployment scripts

# Load deployment-specific environment variables if they exist
DEPLOYMENT_ENV_FILE="/opt/codedeploy-agent/deployment-root/${DEPLOYMENT_GROUP_ID}/${DEPLOYMENT_ID}/deployment-archive/scripts/deployment.env"
if [ -f "$DEPLOYMENT_ENV_FILE" ]; then
    echo "Loading deployment-specific environment variables from $DEPLOYMENT_ENV_FILE"
    source "$DEPLOYMENT_ENV_FILE"
fi

# Default values (used as fallback)
SERVICE_NAME="${SERVICE_NAME:-authentication}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
IMAGE_URI="${IMAGE_URI:-}"
STACK_NAME="${STACK_NAME:-authentication}"

# CodeDeploy specific variables
DEPLOYMENT_ID="${DEPLOYMENT_ID}"
DEPLOYMENT_GROUP_ID="${DEPLOYMENT_GROUP_ID}"
APPLICATION_NAME="${APPLICATION_NAME}"
DEPLOYMENT_GROUP_NAME="${DEPLOYMENT_GROUP_NAME}"

# Docker Swarm specific variables
CERTIFICATE_PASSWORD="${CERTIFICATE_PASSWORD:-}"

# Log all variables for debugging
echo "Environment variables:"
echo "  SERVICE_NAME: ${SERVICE_NAME}"
echo "  ENVIRONMENT: ${ENVIRONMENT}"
echo "  IMAGE_URI: ${IMAGE_URI}"
echo "  STACK_NAME: ${STACK_NAME}"
echo "  DEPLOYMENT_ID: ${DEPLOYMENT_ID}"
echo "  DEPLOYMENT_GROUP_ID: ${DEPLOYMENT_GROUP_ID}"
echo "  APPLICATION_NAME: ${APPLICATION_NAME}"
echo "  DEPLOYMENT_GROUP_NAME: ${DEPLOYMENT_GROUP_NAME}" 