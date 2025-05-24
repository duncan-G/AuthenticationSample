#!/bin/bash

working_dir=$(pwd)

# Delete dangling images
docker container prune -f

# Delete volumes
docker volume prune -a -f

# Pull images
docker pull dpage/pgadmin4:latest
docker pull mcr.microsoft.com/dotnet/aspire-dashboard:latest
docker pull theduncangichimu/postgres:latest

# Build protoc-gen image
docker build -t protoc-gen-grpc-web:latest ./Microservices/.builds/protoc-gen

# Build Postgres Image
postgres_image_name="authentication-sample/postgres"
cd "Microservices/.builds/postgres"
docker build -t $postgres_image_name:latest .
cd $working_dir