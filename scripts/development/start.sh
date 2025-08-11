#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../utils/print-utils.sh"
source "$SCRIPT_DIR/../utils/aws-utils.sh"
source "$SCRIPT_DIR/../utils/common.sh"


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
start_all=false
start_all_containers=false

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -a, --all                           Start all services"
    echo "  -A, --all-containers                Start all services with microservices in containers"
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
while getopts ":aAcCbBDdMmp-:" opt; do
    case ${opt} in
        a ) start_all=true ;;
        A ) start_all=true; start_all_containers=true ;;
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
            all ) start_all=true ;;
            all-containers ) start_all=true; start_all_containers=true ;;
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

load_secrets() {
    local secret_name="$1"
    
    local profile="developer"
    local region="us-west-1"
    local env_template_path="$PROJECT_ROOT/infrastructure/.env.template.dev"
    local prefix="Infrastructure_"

    if ! check_jq; then
        exit 1
    fi

    if ! check_aws_cli; then
        exit 1
    fi

    # Check if AWS profile is valid
    if ! check_aws_profile "$profile"; then
        exit 1
    fi

    if ! check_aws_authentication "$profile"; then
        exit 1
    fi

    
    # Validate required parameters
    if [[ -z $secret_name ]]; then
        print_error "Secret name is required"
        return 1
    fi
    
    print_info "Loading secrets from AWS Secrets Manager..."
    
    # Get secrets from AWS Secrets Manager
    local secret_json
    if ! secret_json=$(get_secret "$secret_name" "$profile" "$region" "$prefix"); then
        print_error "Failed to retrieve secrets from AWS Secrets Manager"
        return 1
    fi

    # Read template file and verify all required secrets exist
    print_info "Verifying secrets..."
    
    if [ ! -f "$env_template_path" ]; then
        print_error "Environment template file not found: $env_template_path"
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi
        
        # Extract variable name before = sign
        var_name=$(echo "$line" | cut -d'=' -f1)

        # Create prefixed variable name
        var_name="${var_name#"$prefix"}"
        
        # Check if prefixed variable exists in secrets
        if ! echo "$secret_json" | jq -e --arg key "$var_name" 'has($key)' >/dev/null; then
            print_error "Required secret not found: $var_name"
            return 1
        fi
    done < "$env_template_path"
    
    print_success "✓ All required secrets verified"
    
    # Parse JSON secrets and export as environment variables
    while IFS="=" read -r key value; do
        if [[ -n $key && -n $value ]]; then
            # Remove prefix from key if it exists
            key="${key#"$prefix"}"
            export "$key"="$value"
            print_success "✓ Loaded secret: $key"
        fi
    done < <(echo "$secret_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    
    print_success "Secrets loaded successfully"
    return 0
    
}

# Function to start the client
start_client() {
    print_info "Starting client application..."
    if [ "$client_container" = true ]; then
        "$SCRIPT_DIR/start_client.sh" --container
    else
        "$SCRIPT_DIR/start_client.sh"
    fi
}

# Function to start the backend environment
start_backend_environment() {
    print_info "Starting backend environment..."
    if [ "$generate_certificate" = true ]; then
        "$SCRIPT_DIR/start_backend_environment.sh" --certificate
    else
        "$SCRIPT_DIR/start_backend_environment.sh"
    fi
}

# Function to handle database
handle_database() {
    print_info "Starting database..."
    if [ "$clean_database" = true ]; then
        "$SCRIPT_DIR/start_database.sh" --clean
    else
        "$SCRIPT_DIR/start_database.sh"
    fi
}

# Function to start the microservices
start_microservices() {
    print_info "Starting microservices..."
    if [ "$containerize_microservices" = true ]; then
        "$SCRIPT_DIR/start_microservices.sh" --containerize
    else
        "$SCRIPT_DIR/start_microservices.sh"
    fi
}

# Function to start the proxy
start_proxy() {
    print_info "Starting proxy..."
    "$SCRIPT_DIR/start_proxy.sh"
}

# Main execution
cd "$working_dir"

# If no options are provided, show help
if [ "$client" = false ] && [ "$backend_environment" = false ] && [ "$database" = false ] && [ "$microservices" = false ] && [ "$proxy" = false ] && [ "$start_all" = false ]; then
    show_help
fi

# Handle start all flags
if [ "$start_all" = true ]; then
    database=true
    backend_environment=true
    client=true
    microservices=true
    
    # If starting all in containers, set container flags
    if [ "$start_all_containers" = true ]; then
        proxy=true
        client_container=true
        containerize_microservices=true
    fi
fi

load_secrets "auth-sample-secrets-development"

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