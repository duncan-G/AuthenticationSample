#!/bin/bash

# Exit on error
set -e

working_dir=$(pwd)
# Initialize all boolean flags
client=false
client_container=false
backend_environment=false
generate_certificate=false
database=false
clean_database=false
microservices=false
containerize_microservices=false
proxy=false

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -c, --client                        Start the client application"
    echo "  -C, --client-container              Start the client when running server in containers"
    echo "  -b, --backend                       Start the backend environment"
    echo "  -B, --backend-certificate           Start the backend environment with a new self-signed certificate"
    echo "  -d, --database                      Start the database"
    echo "  -D, --clean-database                Clean and restart the database"
    echo "  -m, --microservices                 Start the microservices"
    echo "  -M, --containerize-microservices    Start microservices in containers"
    echo "  -p, --proxy                         Start the proxy"
    echo "  -h, --help                          Show this help message"
    exit 0
}

# Parse options
while getopts ":cCbBDdMmp-:" opt; do
    case ${opt} in
        c ) client=true ;;
        C ) client=true; client_container=true ;;
        b ) backend_environment=true ;;
        B ) backend_environment=true; generate_certificate=true ;;
        d ) database=true ;;
        D ) database=true; clean_database=true ;;
        m ) microservices=true ;;
        M ) microservices=true; containerize_microservices=true ;;
        p ) proxy=true ;;
        h ) show_help ;;
        - ) case "${OPTARG}" in
            client ) client=true ;;
            client-container ) client=true; client_container=true ;;
            backend ) backend_environment=true ;;
            backend-certificate ) backend_environment=true; generate_certificate=true ;;
            database ) database=true ;;
            clean-database ) clean_database=true ;;
            microservices ) microservices=true ;;
            containerize-microservices ) microservices=true; containerize_microservices=true ;;
            proxy ) proxy=true ;;
            help ) show_help ;;
            * ) echo "Invalid option: --${OPTARG}" >&2; exit 1 ;;
        esac ;;
        \? ) echo "Invalid option: -${OPTARG}" >&2; exit 1 ;;
    esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

# Function to start the client
start_client() {
    echo "Starting client application..."
    script_path="./scripts/start_client.sh"
    if [ "$client_container" = true ]; then
        "$script_path" --container
    else
        "$script_path"
    fi
}

# Function to start the backend environment
start_backend_environment() {
    echo "Starting backend environment..."
    script_path="./scripts/start_backend_environment.sh"
    if [ "$generate_certificate" = true ]; then
        "$script_path" --certificate
    else
        "$script_path"
    fi
}

# Function to handle database
handle_database() {
    echo "Starting database..."
    script_path="./scripts/start_database.sh"
    if [ "$clean_database" = true ]; then
        "$script_path" --clean
    else
        "$script_path"
    fi
}

# Function to start the microservices
start_microservices() {
    echo "Starting microservices..."
    script_path="./scripts/start_microservices.sh"
    if [ "$containerize_microservices" = true ]; then
        "$script_path" --containerize
    else
        "$script_path"
    fi
}

# Function to start the proxy
start_proxy() {
    echo "Starting proxy..."
    script_path="./scripts/start_proxy.sh"
    "$script_path"
}
# Main execution
cd "$working_dir"


# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a
else
    echo "Warning: .env file not found. Please create one with CERTIFICATE_PASSWORD variable."
    exit 1
fi

# Verify required environment variables
if [ -z "$CERTIFICATE_PASSWORD" ]; then
    echo "Error: CERTIFICATE_PASSWORD is not set in .env file"
    exit 1
fi


# If no options are provided, show help
if [ "$client" = false ] && [ "$backend_environment" = false ] && [ "$database" = false ] && [ "$microservices" = false ] && [ "$proxy" = false ]; then
    show_help
fi

# Start components based on flags
if [ "$database" = true ]; then
    handle_database
fi

if [ "$backend_environment" = true ]; then
    start_backend_environment
fi

if [ "$client" = true ]; then
    start_client
fi

if [ "$microservices" = true ]; then
    start_microservices
fi

if [ "$proxy" = true ]; then
    start_proxy
fi