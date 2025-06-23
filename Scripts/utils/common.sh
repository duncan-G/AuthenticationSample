#!/bin/bash

#########################################
# Common Utility Functions Script
#########################################

# Source shared print utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print-utils.sh"

# Get script directory
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Get project root directory
get_project_root() {
    local script_dir=$(get_script_dir)
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required environment variable
require_env_var() {
    local var_name="$1"
    if [ -z "${!var_name}" ]; then
        print_error "Required environment variable $var_name is not set"
        exit 1
    fi
}

# Validate file exists
require_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        print_error "Required file $file_path does not exist"
        exit 1
    fi
}

# Validate directory exists
require_directory() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        print_error "Required directory $dir_path does not exist"
        exit 1
    fi
}

# Export functions so they can be used by other scripts
export -f get_script_dir get_project_root command_exists require_env_var require_file require_directory
