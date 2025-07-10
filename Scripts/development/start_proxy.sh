#!/bin/bash

# Source the deployment utilities
source "$(dirname "$0")/../deployment/deployment_utils.sh"

# Get current version from running Envoy service if it exists
CURRENT_VERSION=$(docker service inspect envoy_app 2>/dev/null | jq -r '.[0].Spec.Labels.version // "0"')

# Increment version
VERSION=$((CURRENT_VERSION + 1))

echo "Starting Envoy proxy"
docker config create envoy_config_$VERSION Infrastructure/envoy/dev/envoy-debug.yaml
docker config create envoy_clusters_$VERSION Infrastructure/envoy/dev/discovery/envoy.cds.yaml
docker config create envoy_secrets_$VERSION Infrastructure/envoy/dev/discovery/envoy.sds.yaml
docker config create envoy_routes_$VERSION Infrastructure/envoy/dev/discovery/envoy.rds.yaml

echo "Deploying Envoy proxy"
env VERSION=$VERSION docker stack deploy --compose-file Infrastructure/envoy/dev/envoy.stack.debug.yaml envoy

# Wait for deployment
if ! wait_for_deployment "envoy_app" "$VERSION"; then
    echo "Deployment failed or timed out. Cleaning up new configs..."
    delete_config "envoy_config_$VERSION"
    delete_config "envoy_clusters_$VERSION"
    delete_config "envoy_secrets_$VERSION"
    delete_config "envoy_routes_$VERSION"
    echo "Cleanup complete. Exiting."
    exit 1
fi

if [ "$CURRENT_VERSION" -gt 0 ]; then

    echo "Deleting old Envoy configs"
    delete_config "envoy_config_$CURRENT_VERSION"
    delete_config "envoy_clusters_$CURRENT_VERSION"
    delete_config "envoy_secrets_$CURRENT_VERSION"
    delete_config "envoy_routes_$CURRENT_VERSION"
fi
