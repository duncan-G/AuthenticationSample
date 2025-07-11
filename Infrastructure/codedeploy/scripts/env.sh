#!/bin/bash

# Environment variables for CodeDeploy deployment
# This file is sourced by all deployment scripts

# Default values (used as fallback)

# Service configuration
SERVICE_NAME=$SERVICE_NAME
ENVIRONMENT=$ENVIRONMENT
STACK_FILE=$STACK_FILE

# AWS Secrets Manager configuration
SECRET_NAME=$SECRET_NAME

# Certificate validation (set to "true" to enable certificate validation)
VALIDATE_CERTIFICATES=$VALIDATE_CERTIFICATES
CERT_PREFIX=$CERT_PREFIX
