# Authentication Sample Application

This is a modern microservices-based authentication sample application that demonstrates best practices in building secure, scalable, and observable services. The application uses a combination of .NET microservices, Envoy proxy, and modern web technologies.

## Architecture Overview

The application consists of several key components:

1. **Authentication Service**: A .NET gRPC service that handles user authentication
2. **Client Application**: A Next.js web application that provides the user interface
3. **Envoy Proxy**: A high-performance edge proxy that handles routing, TLS termination, and protocol translation
4. **PostgreSQL Database**: Stores user data and authentication information
5. **Aspire Dashboard**: Provides observability and monitoring capabilities in development.
6. **PgAdmin**: Web-based PostgreSQL administration tool

## Prerequisites

- Docker Desktop with Docker Swarm enabled
- .NET 9 SDK
- Node.js 22+ and npm
- OpenSSL (for certificate generation)
- bash

## Environment Setup

The application uses a layered environment configuration approach. Each component has an `.env.conf` template file that documents its required environment variables.

### Setting Up Environment Files

1. **Root Environment**:
   ```bash
   # Copy the root environment template
   cp .env.conf .env
   # Edit .env and fill in the required values
   ```

2. **Service Environments**:
   ```bash
   # For each service, copy its environment template
   cp Microservices/Authentication/src/Authentication.Grpc/.env.conf Microservices/Authentication/src/Authentication.Grpc/.env
   # Edit the .env file and fill in the required values
   ```

3. **Container Overrides** (if needed):
   ```bash
   # For containerized deployment, create .env.docker files
   cp Microservices/Authentication/src/Authentication.Grpc/.env.docker.conf Microservices/Authentication/src/Authentication.Grpc/.env.docker
   # Edit .env.docker with container-specific values
   ```

### Environment File Hierarchy

Environment variables are loaded in this order (later files override earlier ones):
1. Root `.env`
2. Service-specific `.env`
3. Service-specific `.env.docker` (when running in containers)

### Security Notes

- All `.env` and `.env.docker` files are git-ignored
- `.env.conf` templates are committed to the repository
- Never commit sensitive values in environment files
- Use strong, unique passwords for each environment

## Starting the Application

The application can be started using the `start.sh` script with various options:

```bash
# Start all components
./start.sh -a

# Start specific components
./start.sh -b  # Start backend environment (Docker Swarm, network, certificates)
./start.sh -d  # Start or restart database (PostgreSQL and PgAdmin)
./start.sh -D  # Delete data volumes and then Start or restart database
./start.sh -m  # Start microservices
./start.sh -M  # Start microservices in docker containers
./start.sh -p  # Start or restart proxy (Envoy) (Only valid when running microservices in containers)
./start.sh -c  # Start client application
./start.sh -C  # Start client applications when microservices are running in containers

```

### Component Ports

- **Client Application**: https://localhost:3000
- **Authentication Service**: https://localhost:8000
- **PostgreSQL**: localhost:5432
- **Pgadmin**: localhost:5050
- **Apsire Dashboard** localhost:18888
- **Envoy Proxy**: (When running microservices in containers)
  - Main HTTPS: https://localhost:10000
  - Admin Interface: http://localhost:4000
  - Aspire Dashboard: http://localhost:4001
  - PgAdmin: http://localhost:4002

## Stopping the Application

To stop the application, use the `stop.sh` script:

```bash
./stop.sh
```

This will:
1. Stop all running services
2. Remove Docker stacks
3. Clean up temporary files
4. Leave the Docker Swarm (use `-f` to force leave)

## Development

### Directory Structure

- `Microservices/`: Contains all backend services
  - `Authentication/`: The authentication gRPC service
  - `.builds/`: Docker compose and configuration files
- `Clients/`: Contains the Next.js client application
- `Libraries/`: Shared backed libraries and utilities
- `scripts/`: Utility scripts for development and deployment
- `certificates/`: Generated TLS certificates
- `logs/`: Application logs (Can also use aspire dashboard)
- `pids/`: Process ID files for local development

### Key Scripts

- `start.sh`: Main script to start components
- `stop.sh`: Script to stop all components
- `setup.sh`: Initial setup script
- `install.sh`: Installation script for dependencies
- `scripts/start_backend_environment.sh`: Sets up Docker Swarm and certificates
- `scripts/start_database.sh`: Manages PostgreSQL and PgAdmin
- `scripts/start_microservices.sh`: Starts the authentication service
- `scripts/start_proxy.sh`: Manages the Envoy proxy
- `scripts/start_client.sh`: Starts the Next.js client


## Observability

- Aspire Dashboard provides real-time monitoring
- OpenTelemetry integration for distributed tracing
- Detailed access logging through Envoy
