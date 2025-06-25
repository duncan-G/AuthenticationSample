#!/bin/bash

#########################################
# Input Validation Utilities Script
# Shared validation functions for scripts
#########################################

# Source shared utilities
UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UTILS_SCRIPT_DIR/print-utils.sh"

# Validate service name
validate_service_name() {
    local service_name="$1"
    
    if [ -z "$service_name" ]; then
        print_error "Service name is required"
        return 1
    fi
    
    if [[ ! "$service_name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        print_error "Service name can only contain letters, numbers, and hyphens"
        return 1
    fi
    
    return 0
}

# Validate environment name
validate_environment() {
    local environment="$1"
    
    if [ -z "$environment" ]; then
        print_error "Environment is required"
        return 1
    fi
    
    case "$environment" in
        "development"|"staging"|"production")
            return 0
            ;;
        *)
            print_error "Environment must be one of: development, staging, production"
            return 1
            ;;
    esac
}

# Validate version format
validate_version() {
    local version="$1"
    
    if [ -z "$version" ]; then
        print_error "Version is required"
        return 1
    fi
    
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_error "Version must be in format: X.Y.Z"
        return 1
    fi
    
    return 0
}

# Export functions so they can be used by other scripts
export -f validate_service_name validate_environment validate_version
