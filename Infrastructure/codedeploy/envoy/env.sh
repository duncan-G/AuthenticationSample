#!/bin/bash

# Environment variables for CodeDeploy deployment
# This file is sourced by all deployment scripts

# Default values (used as fallback)
SERVICE_NAME="${SERVICE_NAME:-envoy}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
IMAGE_URI="${IMAGE_URI:-}"
STACK_NAME="${STACK_NAME:-envoy}"
VERSION="${VERSION:-}"
DOMAIN="${DOMAIN:-example.com}"
APP_NAME="${APP_NAME:-example-app}"
SECRET_NAME="${SECRET_NAME:-}"

# CodeDeploy specific variables
DEPLOYMENT_ID="${DEPLOYMENT_ID}"
DEPLOYMENT_GROUP_ID="${DEPLOYMENT_GROUP_ID}"
DEPLOYMENT_GROUP_NAME="${DEPLOYMENT_GROUP_NAME}"

# Log all variables for debugging
echo "Environment variables:"
echo "  SERVICE_NAME: ${SERVICE_NAME}"
echo "  ENVIRONMENT: ${ENVIRONMENT}"
echo "  IMAGE_URI: ${IMAGE_URI}"
echo "  STACK_NAME: ${STACK_NAME}"
echo "  VERSION: ${VERSION}"
echo "  APP_NAME: ${APP_NAME}"
echo "  DOMAIN: ${DOMAIN}"
echo "  DEPLOYMENT_ID: ${DEPLOYMENT_ID}"
echo "  DEPLOYMENT_GROUP_ID: ${DEPLOYMENT_GROUP_ID}"
echo "  DEPLOYMENT_GROUP_NAME: ${DEPLOYMENT_GROUP_NAME}" 