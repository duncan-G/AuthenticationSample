#!/bin/bash

# Usage: get_service_status <service_name> <expected_version>
get_service_status() {
    local service_name=$1
    local expected_version=$2
    local state=$(docker service inspect "${service_name}" 2>/dev/null)
    
    if [ -z "$state" ]; then
        echo "not_found" >&2
        echo "not_found"
        return
    fi

    local update_started_at=$(echo $state | jq -r '.[0].UpdateStatus.StartedAt')
    local update_status=$(echo $state | jq -r '.[0].UpdateStatus.State')
    local replicas=$(docker service ls -f "name=${service_name}" --format "{{.Replicas}}" 2>/dev/null)
    local current_version=$(echo $state | jq -r '.[0].Spec.Labels.version // "0"')

    # Check if version matches
    if [ "$current_version" != "$expected_version" ]; then
        echo "version_mismatch" >&2
        echo "version_mismatch"
        return
    fi

    if [[ $update_status == "null" ]]; then
        # First deployment - check replicas
        if [ -z "$replicas" ]; then
            echo "no_replicas" >&2
            echo "no_replicas"
            return
        fi
        
        replicated=$(echo "$replicas" | awk -F'/' '{print $1}')
        total_replicas=$(echo "$replicas" | awk -F'/' '{print $2}')
        
        if [[ $replicated != $total_replicas ]]; then
            echo "creating" >&2
            echo "creating"
        else
            echo "completed" >&2
            echo "completed"
        fi
    else
        if [[ $update_status == "updating" ]]; then
            echo "updating" >&2
            echo "updating"
        elif [[ $update_status == "completed" ]]; then
            echo "completed" >&2
            echo "completed"
        elif [[ $update_status == "rollback_completed" ]]; then
            echo "rollback_completed" >&2
            echo "rollback_completed"
        else
            echo "$update_status" >&2
            echo "$update_status"
        fi
    fi
}

# Usage: is_deployment_complete <service_name> <expected_version>
is_deployment_complete() {
    local service_name=$1
    local expected_version=$2
    local status=$(get_service_status "$service_name" "$expected_version")
    echo "Current status for $service_name: $status" >&2
    
    if [[ $status == "completed" ]]; then
        return 0
    elif [[ $status == "rollback_completed" || $status == "version_mismatch" ]]; then
        return 2
    else
        return 1
    fi
}

# Usage: get_deployment_status <service_name>
get_deployment_status() {
    local service_name=$1
    local state=$(docker service inspect "${service_name}" 2>/dev/null)
    
    if [ -z "$state" ]; then
        echo "Service not found"
        return
    fi

    local replicas=$(docker service ls -f "name=${service_name}" --format "{{.Replicas}}" 2>/dev/null)
    local update_status=$(echo "$state" | jq -r '.[0].UpdateStatus.State // "null"')
    local update_message=$(echo "$state" | jq -r '.[0].UpdateStatus.Message // ""')
    local current_version=$(echo "$state" | jq -r '.[0].Spec.Labels.version // "0"')
    
    echo "Version: $current_version"
    echo "Replicas: $replicas"
    if [ "$update_status" != "null" ]; then
        echo "Update Status: $update_status"
        if [ ! -z "$update_message" ]; then
            echo "Update Message: $update_message"
        fi
    fi
}

# Usage: wait_for_deployment <service_name> <expected_version>
# Uses Docker service update and restart policy timeouts
wait_for_deployment() {
    local service_name=$1
    local expected_version=$2
    local state=$(docker service inspect "${service_name}" 2>/dev/null)
    
    # Get update and restart policy settings
    # Convert times from nanoseconds to seconds
    local monitor_ns=$(echo "$state" | jq -r '.[0].Spec.UpdateConfig.Monitor // "15000000000"')
    local monitor_seconds=$((monitor_ns / 1000000000))
    local restart_window_ns=$(echo "$state" | jq -r '.[0].Spec.TaskTemplate.RestartPolicy.Window // "120000000000"')
    local restart_seconds=$((restart_window_ns / 1000000000))
    
    # Use the longer of monitor time or restart window as our timeout
    local timeout=$((monitor_seconds > restart_seconds ? monitor_seconds : restart_seconds))
    local counter=0
    local last_status=""

    echo "Waiting for $service_name to be deployed (timeout: ${timeout}s)..."
    while [ $counter -lt $timeout ]; do
        is_deployment_complete "$service_name" "$expected_version"
        local deploy_status=$?
        
        if [ $deploy_status -eq 0 ]; then
            echo "$service_name version $expected_version is successfully deployed"
            return 0
        elif [ $deploy_status -eq 2 ]; then
            echo "Deployment of $service_name failed or rolled back"
            echo "----------------------------------------"
            echo "Service logs for $service_name:"
            docker service logs --tail 50 "$service_name" 2>&1 || echo "Failed to fetch logs"
            echo "----------------------------------------"
            return 2
        fi
        
        # Get and display current deployment status
        current_status=$(get_deployment_status "$service_name")
        if [ "$current_status" != "$last_status" ]; then
            echo "----------------------------------------"
            echo "Current deployment status:"
            echo "$current_status"
            echo "----------------------------------------"
            last_status="$current_status"
        fi
        
        echo "Waiting for $service_name to update... ($((timeout-counter))s remaining)"
        sleep 2
        counter=$((counter + 2))
    done

    echo "Timeout reached waiting for $service_name deployment"
    echo "Final deployment status:"
    get_deployment_status "$service_name"
    echo "----------------------------------------"
    echo "Service logs for $service_name:"
    docker service logs --tail 50 "$service_name" 2>&1 || echo "Failed to fetch logs"
    echo "----------------------------------------"
    return 1
}

# Usage: delete_config <config_name>
# Returns 0 if config was deleted or didn't exist, 1 if deletion failed
delete_config() {
    local config_name=$1
    if docker config inspect "$config_name" >/dev/null 2>&1; then
        echo "Removing config: $config_name"
        if docker config rm "$config_name"; then
            return 0
        else
            echo "Failed to delete config: $config_name"
            return 1
        fi
    else
        echo "Config does not exist: $config_name"
        return 0
    fi
}
