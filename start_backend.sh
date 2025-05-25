#!/bin/bash

working_dir=$(pwd)

containerize_microservices=false

# Function to check if certificate is valid
check_certificate() {
    local cert_path="$1"
    local cert_password="$2"
    
    if [ ! -f "$cert_path" ]; then
        return 1
    fi
    
    # Check if certificate is valid and not expired
    if ! openssl pkcs12 -in "$cert_path" -passin pass:"$cert_password" -nokeys 2>/dev/null | \
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
    
    # Add to keychain and trust it
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$temp_cert"
    
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
    if check_certificate "$cert_path" "$cert_password"; then
        echo "Using existing valid certificate"
        return 0
    fi
    
    echo "Generating new self-signed certificate"
    
    # Generate private key and CSR
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -subj "/CN=localhost" \
        -addext "subjectAltName = DNS:localhost,IP:127.0.0.1" \
        -keyout "$cert_dir/aspnetapp.key" \
        -out "$cert_dir/aspnetapp.crt"

    # Convert to PFX format
    sudo openssl pkcs12 -export \
        -out "$cert_path" \
        -inkey "$cert_dir/aspnetapp.key" \
        -in "$cert_dir/aspnetapp.crt" \
        -passout pass:"$cert_password"

    # Clean up key and crt files
    sudo rm "$cert_dir/aspnetapp.key" "$cert_dir/aspnetapp.crt"

    # Ensure correct permissions
    sudo chmod 644 "$cert_path"
    
    echo "Certificate generated successfully"
    
    # Trust the certificate
    trust_certificate "$cert_dir" "$cert_password"
}

# Parse options
while getopts ":c-containerize_microservices" opt; do
  case ${opt} in
    c | containerize_microservices ) 
      containerize_microservices=true
      ;;
    \? ) 
      echo "Usage: $0 [-c | -containerize_microservices]"
      exit 1
      ;;
  esac
done

# Shift parsed options so remaining arguments can be accessed
shift $((OPTIND -1))

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

# Run Aspire Dashboard
echo "Running Aspire Dashboard"
docker stack deploy --compose-file Microservices/.builds/aspire/aspire.stack.debug.yaml aspire

# Run Postgres
bash start_database.sh -r

# Generate Authentication grpc services
echo "Generating grpc services"
bash Microservices/.builds/protoc-gen/gen-grpc-web.sh \
    -i $working_dir/Microservices/Authentication/src/Authentication.Grpc/Protos/greet.proto \
    -o $working_dir/Clients/authentication-sample/src/app/services
docker container rm protoc-gen-grpc-web

# Start Next.js application
echo "Starting client..."
osascript -e "tell application \"Terminal\" to do script \"cd $working_dir/Clients/authentication-sample && npm run dev \""
cd $working_dir

# Deploy Authentication microservice if containerization is enabled
if [ "$containerize_microservices" = true ]; then
    # Create certificates directory if it doesn't exist
    echo "Creating certificates"
    cert_dir="/Volumes/aspnet_certificates"
    sudo mkdir -p "$cert_dir"

    # Generate certificate
    CERTIFICATE_PASSWORD=YourSecurePassword123!
    generate_certificate "$cert_dir" "$CERTIFICATE_PASSWORD"

    echo "Building Authentication service"
    cd $working_dir/Microservices/Authentication
    env ContainerRepository=authentication-sample/authentication \
      dotnet publish --os linux --arch x64 /t:PublishContainer
    cd ../..

    echo "Deploying Authentication service to swarm"
    env IMAGE_NAME=authentication-sample/authentication \
        ENV_FILE=$working_dir/Microservices/Authentication/src/Authentication.Grpc/.env \
        OVERRIDE_STAGING_ENV_FILE=$working_dir/Microservices/Authentication/src/Authentication.Grpc/.env.staging \
        CERTIFICATE_PASSWORD=$CERTIFICATE_PASSWORD \
        CERTIFICATE_PATH=$cert_dir \
        docker stack deploy --compose-file Microservices/.builds/service.stack.debug.yaml authentication
fi
