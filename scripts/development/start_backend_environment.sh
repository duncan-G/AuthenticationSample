#!/bin/bash

working_dir=$(pwd)
generate_new_certificate=false

# Function to check if certificate is valid
check_certificate() {
    local cert_dir="$1"
    local cert_password="$2"
    
    echo "Checking ASP.NET Core developer certificate..."
    
    # Check if ASP.NET Core developer certificate exists
    if ! dotnet dev-certs https --check &>/dev/null; then
        echo "No ASP.NET Core developer certificate found"
        return 1
    fi
    echo "✓ ASP.NET Core developer certificate exists"
    
    # Check if exported certificate files exist
    if [ ! -f "$cert_dir/aspnetapp.pfx" ]; then
        echo "Missing exported PFX certificate file: $cert_dir/aspnetapp.pfx"
        return 1
    fi
    if [ ! -f "$cert_dir/cert.pem" ]; then
        echo "Missing exported PEM certificate file: $cert_dir/cert.pem"
        return 1
    fi
    echo "✓ Exported certificate files exist"
    
    # Check if certificate is not expired (valid for at least 30 days)
    if ! openssl pkcs12 -in "$cert_dir/aspnetapp.pfx" -passin pass:"$cert_password" -nokeys 2>/dev/null | \
         openssl x509 -noout -checkend 2592000 2>/dev/null; then
        echo "Certificate will expire within 30 days or is already expired"
        return 1
    fi
    echo "✓ Certificate is valid for at least 30 more days"
    
    echo "✓ All certificate checks passed"
    return 0
}

# Function to generate and export certificates
generate_certificate() {
    local cert_dir="$1"
    local cert_password="$2"
    
    # Check if certificate exists and is valid
    if [ "$generate_new_certificate" = false ] && check_certificate "$cert_dir" "$cert_password"; then
        echo "Using existing valid ASP.NET Core developer certificate"
        return 0
    fi
    
    echo "Setting up ASP.NET Core developer certificate"

    rm -rf "$cert_dir"
    mkdir "$cert_dir"

    # Clean up any existing untrusted certificates
    dotnet dev-certs https --clean
    
    # Create and trust the ASP.NET Core developer certificate
    dotnet dev-certs https --trust
    
    echo "Exporting certificates for container use..."
    
    # Export the certificate for use in containers
    dotnet dev-certs https -ep "$cert_dir/aspnetapp.pfx" -p "$cert_password"
    
    # Also export in PEM format for other uses
    dotnet dev-certs https -ep "$cert_dir/cert.pem" --format PEM
    
    # Extract private key from PFX for Docker secrets
    openssl pkcs12 -in "$cert_dir/aspnetapp.pfx" -nocerts -out "$cert_dir/cert.key" -passin pass:"$cert_password" -passout pass: -nodes
    
    echo "ASP.NET Core developer certificate created, trusted, and exported successfully"
}

# Parse options
while getopts ":c-certificate" opt; do
  case ${opt} in
    c | certificate ) 
      generate_new_certificate=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -certificate]"
      exit 1
      ;;
  esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))


# Verify required environment variables
if [ -z "$CERTIFICATE_PASSWORD" ]; then
    print_error "CERTIFICATE_PASSWORD is not set in environment"
    exit 1
fi
if [ -z "$ASPIRE_BROWSER_TOKEN" ]; then
    print_error "ASPIRE_BROWSER_TOKEN is not set in environment"
    exit 1
fi

# Start Docker Swarm
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    echo "Leaving existing Docker Swarm"
    docker swarm leave --force
fi
echo "Initializing Docker Swarm"
docker swarm init

# Create network
echo "Creating Docker network for swarm called net"
if docker network inspect net &>/dev/null; then
    docker network rm net
fi
docker network create -d overlay --attachable --driver overlay net

# Generate certificate
cert_dir="$working_dir/certificates"
generate_certificate "$cert_dir" "$CERTIFICATE_PASSWORD"

# Create Docker secrets from the generated certificates
# Remove existing secrets if they exist
for secret in cert.pem cert.key aspnetapp.pfx; do
    if docker secret inspect "$secret" &>/dev/null; then
        docker secret rm "$secret"
    fi
done

# Create new secrets
docker secret create cert.pem "$cert_dir/cert.pem"
docker secret create cert.key "$cert_dir/cert.key"
docker secret create aspnetapp.pfx "$cert_dir/aspnetapp.pfx"

# Run Aspire Dashboard
echo "Running Aspire Dashboard"
env ASPIRE_BROWSER_TOKEN=$ASPIRE_BROWSER_TOKEN \
    docker stack deploy --compose-file infrastructure/aspire/aspire.stack.debug.yaml otel-collector
