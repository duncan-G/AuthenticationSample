#!/bin/bash

working_dir=$(pwd)

# Delete dangling images, volumes, configs, secrets, and networks
docker container prune -f
docker volume prune -f
docker network prune -f

# Pull images
docker pull mcr.microsoft.com/dotnet/aspire-dashboard:latest
docker pull envoyproxy/envoy:v1.34-latest
docker pull redis:latest

# Pull mcp servers
docker pull mcp/aws-documentation:latest
docker pull mcp/aws-terraform:latest

# Build protoc-gen image
docker build -t protoc-gen-grpc-web:latest ./infrastructure/protoc-gen

# Install npm dependencies
cd "clients/auth-sample"
npm ci
cd $working_dir

# Build Postgres Image
postgres_image_name="auth-sample/postgres"
cd "infrastructure/postgres"
docker build -t $postgres_image_name:latest .
cd $working_dir

