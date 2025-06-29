#!/usr/bin/env bash
# trigger-certificate-renewal.sh - Triggers a one-off Docker task for certificate renewal
# This script is called by the daemon to run certificate renewal in a containerized environment

set -Eeuo pipefail

readonly LOG_FILE="/var/log/certificate-renewal-trigger.log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Docker image configuration
readonly DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-certificate-renewal}"
readonly DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-latest}"
readonly DOCKER_IMAGE="${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"

# Environment variables to pass to the container
readonly CONTAINER_ENV_VARS=(
  "S3_BUCKET"
  "CERT_PREFIX"
  "DOMAIN"
  "INTERNAL_DOMAIN"
  "EMAIL"
  "AWS_ROLE_NAME"
  "WILDCARD"
  "RENEWAL_THRESHOLD_DAYS"
  "CERT_OUTPUT_DIR"
)

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  printf '[ %s ] %s\n' "$(timestamp)" "$*" | tee -a "$LOG_FILE" >&2
}

on_error() {
  local ec=$? line=$1
  log "ERROR: line $line exited with code $ec"
  exit "$ec"
}
trap 'on_error $LINENO' ERR

# Validate prerequisites
validate_prerequisites() {
  log "Validating prerequisites"
  
  # Check if Docker is available
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: Docker is not available"
    exit 1
  fi
  
  # Check if Docker daemon is running
  if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker daemon is not running"
    exit 1
  fi
  
  log "Prerequisites validated successfully"
}

# Build Docker image if it doesn't exist
build_docker_image() {
  log "Building Docker image: $DOCKER_IMAGE"
  
  if docker build -t "$DOCKER_IMAGE" "$SCRIPT_DIR"; then
    log "Docker image built successfully"
  else
    log "ERROR: Failed to build Docker image"
    exit 1
  fi
}

# Check if Docker image exists
image_exists() {
  docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${DOCKER_IMAGE}$"
}

# Run the certificate renewal container
run_certificate_renewal() {
  log "Triggering certificate renewal via Docker container"
  
  # Check if image exists, build if not
  if ! image_exists; then
    build_docker_image
  fi
  
  # Build Docker run command with environment variables
  local docker_cmd=(
    docker run --rm
    --network host
    -v /var/run/docker.sock:/var/run/docker.sock
  )
  
  # Add environment variables
  for var in "${CONTAINER_ENV_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
      docker_cmd+=("-e" "$var=${!var}")
    fi
  done
  
  # Add the image name
  docker_cmd+=("$DOCKER_IMAGE")
  
  # Run the container
  log "Running certificate renewal container"
  
  if "${docker_cmd[@]}"; then
    log "Certificate renewal completed successfully"
    return 0
  else
    log "ERROR: Certificate renewal failed"
    return 1
  fi
}

# Main function
main() {
  log "Certificate renewal trigger started"
  
  # Validate prerequisites
  validate_prerequisites
  
  # Run certificate renewal
  if run_certificate_renewal; then
    log "Certificate renewal trigger completed successfully"
    exit 0
  else
    log "Certificate renewal trigger failed"
    exit 1
  fi
}

# Run main function with all arguments
main "$@" 