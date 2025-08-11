#!/bin/bash

# Source the deployment utilities
source "$(dirname "$0")/../deployment/deployment_utils.sh"

# Get current version from running Envoy service if it exists
CURRENT_VERSION=$(docker service inspect envoy_app 2>/dev/null | jq -r '.[0].Spec.Labels.version // "0"')

# Increment version
VERSION=$((CURRENT_VERSION + 1))

# Set environment variables for RDS config
export ALLOWED_HOSTS="localhost,localhost:10000"
export ALLOWED_ORIGINS="https://localhost:3000"

# Process comma-separated origins into YAML format
IFS=',' read -ra ORIGINS <<< "$ALLOWED_ORIGINS"
ORIGIN_YAML=""
for origin in "${ORIGINS[@]}"; do
    # Trim whitespace and add YAML entry
    origin=$(echo "$origin" | sed 's/^[ \t]*//;s/[ \t]*$//')
    ORIGIN_YAML+="          - prefix: \"https://$origin\"\n"
done
export PROCESSED_ORIGINS=$(echo -e "$ORIGIN_YAML" | sed '$d') # Remove last newline

echo "Starting Envoy proxy with unified configuration"

# Create temporary directory for config processing
TEMP_DIR=$(mktemp -d)

# Only envoy.rds.yaml needs environment variable substitution
envsubst < infrastructure/envoy/envoy.rds.yaml > "$TEMP_DIR/envoy.rds.yaml"

# Create docker configs - process RDS, directly use others
docker config create envoy_config_$VERSION infrastructure/envoy/envoy.yaml
docker config create envoy_clusters_$VERSION infrastructure/envoy/envoy.cds.yaml
docker config create envoy_routes_$VERSION "$TEMP_DIR/envoy.rds.yaml"

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "Deploying Envoy proxy"
env VERSION=$VERSION docker stack deploy --compose-file infrastructure/envoy/dev/envoy.stack.debug.yaml envoy

# Wait for deployment
if ! wait_for_deployment "envoy_app" "$VERSION"; then
    echo "Deployment failed or timed out. Cleaning up new configs..."
    delete_config "envoy_config_$VERSION"
    delete_config "envoy_clusters_$VERSION"
    delete_config "envoy_routes_$VERSION"
    echo "Cleanup complete. Exiting."
    exit 1
fi

if [ "$CURRENT_VERSION" -gt 0 ]; then

    echo "Deleting old Envoy configs"
    delete_config "envoy_config_$CURRENT_VERSION"
    delete_config "envoy_clusters_$CURRENT_VERSION"
    delete_config "envoy_routes_$CURRENT_VERSION"
fi
