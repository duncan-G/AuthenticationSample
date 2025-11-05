#!/bin/bash

# Source the deployment utilities
source "$(dirname "$0")/../development/deployment_utils.sh"

# Parse options for containerized microservices targeting
proxy_containerized_microservices=false

while getopts ":c-containerized-microservices" opt; do
  case ${opt} in
    c | containerized-microservices ) 
      proxy_containerized_microservices=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -containerized-microservices]"
      exit 1
      ;;
  esac
done

# Get current version from running Envoy service if it exists
CURRENT_VERSION=$(docker service inspect envoy_app 2>/dev/null | jq -r '.[0].Spec.Labels.version // "0"')

# Increment version
VERSION=$((CURRENT_VERSION + 1))

# Set environment variables for RDS config
export ALLOWED_HOSTS="localhost,localhost:11000"
export ALLOWED_ORIGINS="https://localhost:3000"

# Process comma-separated origins into YAML format
IFS=',' read -ra ORIGINS <<< "$ALLOWED_ORIGINS"
ORIGIN_YAML=""
for origin in "${ORIGINS[@]}"; do
    # Trim whitespace and add YAML entry
    origin=$(echo "$origin" | sed 's/^[ \t]*//;s/[ \t]*$//')
    ORIGIN_YAML+="          - prefix: \"$origin\"\n"
done
export PROCESSED_ORIGINS=$(echo -e "$ORIGIN_YAML" | sed '$d') # Remove last newline

export SNI_DOMAIN="localhost"

if [ "$proxy_containerized_microservices" = true ]; then
    export AUTH_HOST=auth_app
    export AUTH_PORT=443
    export GREETER_HOST=greeter_app
    export GREETER_PORT=443
else
    export AUTH_HOST=host.docker.internal
    export AUTH_PORT=10000
    export GREETER_HOST=host.docker.internal
    export GREETER_PORT=10001
fi

echo "Starting Envoy proxy with unified configuration"

# Use persistent repo-level temp directory for config processing
REPO_ROOT="$(cd "$(dirname "$0")/../.."; pwd)"
TEMP_DIR="$REPO_ROOT/tmp/envoy"
mkdir -p "$TEMP_DIR"

# Only envoy.rds.yaml needs environment variable substitution
envsubst < infrastructure/envoy/config/envoy.rds.yaml > "$TEMP_DIR/envoy.rds.yaml"
envsubst < infrastructure/envoy/config/envoy.cds.yaml > "$TEMP_DIR/envoy.cds.yaml"
envsubst < infrastructure/envoy/config/envoy.yaml > "$TEMP_DIR/envoy.yaml"
envsubst < infrastructure/envoy/config/envoy.sds.yaml > "$TEMP_DIR/envoy.sds.yaml"

# Create docker configs using processed files
docker config create envoy_config_$VERSION "$TEMP_DIR/envoy.yaml"
docker config create envoy_clusters_$VERSION "$TEMP_DIR/envoy.cds.yaml"
docker config create envoy_routes_$VERSION "$TEMP_DIR/envoy.rds.yaml"
docker config create envoy_secrets_$VERSION "$TEMP_DIR/envoy.sds.yaml"


echo "Deploying Envoy proxy"
env VERSION=$VERSION docker stack deploy --compose-file infrastructure/envoy/envoy.stack.debug.yaml envoy

# Wait for deployment
if ! wait_for_deployment "envoy_app" "$VERSION"; then
    echo "Deployment failed or timed out. Cleaning up new configs..."
    delete_config "envoy_config_$VERSION"
    delete_config "envoy_clusters_$VERSION"
    delete_config "envoy_routes_$VERSION"
    delete_config "envoy_secrets_$VERSION"
    echo "Cleanup complete. Exiting."
    exit 1
fi

if [ "$CURRENT_VERSION" -gt 0 ]; then

    echo "Deleting old Envoy configs"
    delete_config "envoy_config_$CURRENT_VERSION"
    delete_config "envoy_clusters_$CURRENT_VERSION"
    delete_config "envoy_routes_$CURRENT_VERSION"
    delete_config "envoy_secrets_$CURRENT_VERSION"
fi
