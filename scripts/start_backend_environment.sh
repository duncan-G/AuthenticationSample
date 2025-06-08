#!/bin/bash

working_dir=$(pwd)

# Function to check if certificate is valid
check_certificate() {
    local cert_dir="$1"
    local cert_password="$2"
    
    # Check both PFX and PEM files
    if [ ! -f "$cert_dir/aspnetapp.pfx" ] || [ ! -f "$cert_dir/cert.pem" ] || [ ! -f "$cert_dir/cert.key" ]; then
        return 1
    fi
    
    # Check if PFX certificate is valid and not expired
    if ! openssl pkcs12 -in "$cert_dir/aspnetapp.pfx" -passin pass:"$cert_password" -nokeys 2>/dev/null | \
         openssl x509 -noout -checkend 2592000 2>/dev/null; then
        return 1
    fi
    
    return 0
}

# Function to trust the certificate
trust_certificate() {
    local cert_dir="$1"
    local cert_password="$2"
    local cert_path="$cert_dir/aspnetapp.pfx"
    local temp_cert="$cert_dir/aspnetapp.crt"
    
    echo "Exporting certificate for trust..."
    
    # Export certificate to .crt format with sudo
    sudo openssl pkcs12 -in "$cert_path" -clcerts -nokeys -out "$temp_cert" -passin pass:"$cert_password"
    
    # Remove existing certificate if it exists
    sudo security remove-trusted-cert -d "$temp_cert" 2>/dev/null || true
    
    # Add to keychain and trust it with more specific trust settings
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain -p ssl -p basic "$temp_cert"
    
    # Also add to user's keychain
    security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain -p ssl -p basic "$temp_cert"
    
    # Clean up temporary file
    sudo rm "$temp_cert"
    
    echo "Certificate has been added to trusted certificates"
}

# Function to generate self-signed certificate
generate_certificate() {
    local cert_dir="$1"
    local cert_password="$2"
    local cert_path="$cert_dir/aspnetapp.pfx"
    
    # Check if certificate exists and is valid
    if check_certificate "$cert_dir" "$cert_password"; then
        echo "Using existing valid certificate"
        return 0
    fi
    
    echo "Generating new self-signed certificate"
    
    # Generate private key and CSR
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -subj "/CN=localhost" \
        -addext "subjectAltName = DNS:localhost,IP:127.0.0.1" \
        -keyout "$cert_dir/cert.key" \
        -out "$cert_dir/cert.pem"

    # Convert to PFX format for .NET
    sudo openssl pkcs12 -export \
        -out "$cert_path" \
        -inkey "$cert_dir/cert.key" \
        -in "$cert_dir/cert.pem" \
        -passout pass:"$cert_password"

    # Ensure correct permissions
    sudo chmod 644 "$cert_dir/cert.pem" "$cert_dir/cert.key" "$cert_path"
    
    echo "Certificates generated successfully"
    
    # Trust the certificate
    trust_certificate "$cert_dir" "$cert_password"
}

# Verify required environment variables
if [ -z "$CERTIFICATE_PASSWORD" ]; then
    echo "Error: CERTIFICATE_PASSWORD is not set in .env file"
    exit 1
fi

if [ -z "$ASPIRE_BROWSER_TOKEN" ]; then
    echo "Error: ASPIRE_BROWSER_TOKEN is not set in .env file"
    exit 1
fi

# Start Docker Swarm
echo "Starting Docker Swarm"
if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
    docker swarm leave --force
fi
docker swarm init

# Create network
echo "Creating Docker network for swarm called net"
docker network prune -f
if docker network inspect net &>/dev/null; then
    docker network rm net
fi
docker network create -d overlay --attachable --driver overlay net

# Create certificates directory if it doesn't exist
echo "Creating certificates"
cert_dir="$working_dir/certificates"
mkdir -p "$cert_dir"

# Generate certificate
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
    docker stack deploy --compose-file Microservices/.builds/aspire/aspire.stack.debug.yaml aspire
