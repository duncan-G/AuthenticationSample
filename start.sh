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

# Validate that every key present in .env.template also exists – and is non-empty – in .env
validate_env_file() {
  local env_file="${1:-.env}"
  local template_file="${2:-.env.template}"

  # Fast-fail on missing files
  if [[ ! -f $env_file ]]; then
    printf '❌  %s not found – create it from %s\n' "$env_file" "$template_file"
    return 1
  fi

  if [[ ! -f $template_file ]]; then
    printf '⚠️   %s not found – skipping validation\n' "$template_file"
    return 0
  fi

  # Grab variable names (ignore blank lines & comments) from each file
  mapfile -t template_keys < <(grep -Ev '^\s*(#|$)' "$template_file" | cut -d'=' -f1 | sort -u)
  mapfile -t env_keys      < <(grep -Ev '^\s*(#|$)' "$env_file"      | cut -d'=' -f1 | sort -u)

  # Detect missing keys with
  mapfile -t missing < <(comm -23 <(printf '%s\n' "${template_keys[@]}") \
                               <(printf '%s\n' "${env_keys[@]}"))
  
  # Detect keys that are present but have empty values
  empty=()
  for key in "${template_keys[@]}"; do
    # Skip keys that are already identified as missing
    if [[ " ${missing[*]} " =~ " ${key} " ]]; then
      continue
    fi
    
    val=$(grep -E "^\s*$key\s*=" "$env_file" | head -n1 | cut -d'=' -f2-)
    [[ -z $val ]] && empty+=("$key")
  done

  # Report & exit
  if ((${#missing[@]} + ${#empty[@]})); then
    [[ ${#missing[@]} -gt 0 ]] && {
      printf '❌  Missing variables:\n'
      printf '    • %s\n' "${missing[@]}"
    }
    [[ ${#empty[@]} -gt 0 ]] && {
      printf '❌  Empty variables:\n'
      printf '    • %s\n' "${empty[@]}"
    }
    return 1
  fi

  printf '✅  %s is valid\n' "$env_file"
}

# Function to start the client
start_client() {
    echo "Starting client application..."
    script_path="./Scripts/start_client.sh"
    if [ "$client_container" = true ]; then
        "$script_path" --container
    else
        "$script_path"
    fi
}

# Function to start the backend environment
start_backend_environment() {
    echo "Starting backend environment..."
    script_path="./Scripts/start_backend_environment.sh"
    if [ "$generate_certificate" = true ]; then
        "$script_path" --certificate
    else
        "$script_path"
    fi
}

# Function to handle database
handle_database() {
    echo "Starting database..."
    script_path="./Scripts/start_database.sh"
    if [ "$clean_database" = true ]; then
        "$script_path" --clean
    else
        "$script_path"
    fi
}

# Function to start the microservices
start_microservices() {
    echo "Starting microservices..."
    script_path="./Scripts/start_microservices.sh"
    if [ "$containerize_microservices" = true ]; then
        "$script_path" --containerize
    else
        "$script_path"
    fi
}

# Function to start the proxy
start_proxy() {
    echo "Starting proxy..."
    script_path="./Scripts/start_proxy.sh"
    "$script_path"
}

# Main execution
cd "$working_dir"

# Validate environment file before starting backend
if ! validate_env_file; then
    echo "Environment validation failed. Please fix the issues above."
    exit 1
fi

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