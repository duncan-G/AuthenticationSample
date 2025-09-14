# Local Development Setup

## Overview

The local development setup provides a complete development environment that mirrors the production architecture using Docker containers and development servers. The setup includes automated scripts for initializing all services, managing dependencies, and configuring the development environment.

## Implementation

### Development Scripts Architecture

The development setup is organized around a set of shell scripts that manage different aspects of the environment:

```bash
scripts/development/
├── setup.sh                    # Initial environment setup
├── start.sh                    # Main service orchestration
├── stop.sh                     # Service shutdown
├── start_backend_environment.sh # Docker Swarm initialization
├── start_database.sh           # Database services
├── start_microservices.sh      # .NET gRPC services
├── start_client.sh             # Next.js frontend
├── start_proxy.sh              # Envoy API gateway
└── restart_microservice.sh     # Individual service restart
```

### Service Orchestration

The system uses Docker Swarm for local container orchestration, providing:

- **Service Discovery**: Automatic service registration and discovery
- **Load Balancing**: Built-in load balancing for containerized services
- **Health Checks**: Automatic service health monitoring
- **Rolling Updates**: Zero-downtime service updates during development

### Environment Configuration

Development environment uses a hierarchical configuration system:

1. **Template Files**: `.env.template` files define required variables
2. **AWS Secrets**: Development secrets loaded from AWS Secrets Manager
3. **Local Overrides**: Local `.env` files for developer-specific settings
4. **Service Configuration**: Individual service configuration files

## Configuration

### Prerequisites

Required software for local development:

```bash
# Core Requirements
- Docker Desktop (with Docker Swarm support)
- .NET SDK 9.0
- Node.js 22+
- bash shell
- jq (JSON processor)

# AWS Tools (for secrets management)
- AWS CLI v2
- AWS SSO configured with developer profile
```

### Initial Setup

Run the automated setup script:

```bash
./setup.sh
```

This script performs:
- Docker image pulls and builds
- npm dependency installation
- Container image preparation
- Development certificate generation

### Environment Variables

Key environment variables for development:

```bash
# Service URLs
NEXT_PUBLIC_AUTH_SERVICE_URL=https://localhost:8080
NEXT_PUBLIC_GREETER_SERVICE_URL=https://localhost:8081

# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=auth_sample
POSTGRES_USER=postgres
POSTGRES_PASSWORD=<from-secrets>

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379

# AWS Configuration
AWS_PROFILE=developer
AWS_REGION=us-west-1

# Observability
ASPIRE_DASHBOARD_URL=http://localhost:18888
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

## Usage

### Starting the Development Environment

#### Full Environment
Start all services with a single command:

```bash
./start.sh -a                    # All services (local microservices)
./start.sh -A                    # All services (containerized microservices)
```

#### Individual Components
Start specific components as needed:

```bash
./start.sh -b                    # Backend environment (Docker Swarm)
./start.sh -d                    # Database services
./start.sh -m                    # Microservices (local .NET processes)
./start.sh -M                    # Microservices (Docker containers)
./start.sh -c                    # Client application
./start.sh -p                    # Proxy (Envoy gateway)
```

#### Service-Specific Options
Additional options for specific scenarios:

```bash
./start.sh -B                    # Backend with new SSL certificate
./start.sh -D                    # Clean database restart
./start.sh -C                    # Client for containerized backend
./start.sh -P                    # Proxy for containerized microservices
```

### Development Workflow

#### Hot Reload Development
The development environment supports hot reload for rapid iteration:

- **Frontend**: Next.js development server with Turbopack
- **Backend**: .NET hot reload with file watching
- **Configuration**: Automatic configuration reload
- **Styles**: Tailwind CSS with hot reload

#### Service Management
Individual services can be managed independently:

```bash
# Restart a specific microservice
scripts/development/restart_microservice.sh auth

# View service logs
docker service logs auth-sample_auth

# Scale services
docker service scale auth-sample_auth=2
```

#### Database Management
Database operations during development:

```bash
# Clean database restart
./start.sh -D

# Access database directly
docker exec -it $(docker ps -q -f name=postgres) psql -U postgres -d auth_sample

# View database logs
docker service logs auth-sample_postgres
```

### Development URLs

Once started, services are available at:

- **Frontend**: https://localhost:3000
- **API Gateway**: https://localhost:8080
- **Aspire Dashboard**: http://localhost:18888
- **PgAdmin**: http://localhost:5050
- **Envoy Admin**: http://localhost:9901

## Testing

### Environment Validation

Verify the development environment is working correctly:

```bash
# Check Docker Swarm status
docker info --format '{{.Swarm.LocalNodeState}}'

# Verify all services are running
docker service ls

# Test frontend connectivity
curl -k https://localhost:3000

# Test API gateway
curl -k https://localhost:8080/health

# Check database connectivity
docker exec -it $(docker ps -q -f name=postgres) pg_isready
```

### Service Health Checks

Each service includes health check endpoints:

```bash
# Frontend health
curl -k https://localhost:3000/api/health

# Auth service health (via gateway)
curl -k https://localhost:8080/auth/health

# Database health
curl -k https://localhost:8080/db/health
```

### Development Testing

Run tests in development environment:

```bash
# Frontend tests
cd clients/auth-sample
npm test

# Backend tests
cd microservices/Auth
dotnet test

# Integration tests
cd microservices/Auth/tests/Auth.IntegrationTests
dotnet test
```

## Troubleshooting

### Common Setup Issues

#### Docker Swarm Not Active
```bash
# Error: Docker Swarm is not active
# Solution: Initialize Docker Swarm
docker swarm init
```

#### Port Conflicts
```bash
# Error: Port already in use
# Solution: Stop conflicting services
./stop.sh
docker system prune -f
```

#### SSL Certificate Issues
```bash
# Error: SSL certificate not trusted
# Solution: Regenerate certificates
./start.sh -B
```

#### AWS Secrets Access
```bash
# Error: Unable to load secrets
# Solution: Login to AWS SSO
aws sso login --profile developer
```

### Service-Specific Issues

#### Frontend Won't Start
```bash
# Check Node.js version
node --version  # Should be 22+

# Clear npm cache
cd clients/auth-sample
rm -rf node_modules package-lock.json
npm install
```

#### Backend Services Failing
```bash
# Check .NET SDK version
dotnet --version  # Should be 9.0+

# Rebuild services
cd microservices/Auth
dotnet clean
dotnet build
```

#### Database Connection Issues
```bash
# Check PostgreSQL container
docker service logs auth-sample_postgres

# Verify database is accessible
docker exec -it $(docker ps -q -f name=postgres) pg_isready -h localhost -p 5432
```

### Performance Issues

#### Slow Startup Times
- Ensure Docker Desktop has sufficient resources allocated
- Use SSD storage for Docker volumes
- Close unnecessary applications during development

#### Memory Usage
- Monitor Docker Desktop resource usage
- Adjust service replica counts for development
- Use containerized microservices for lower memory usage

## Related Features

- [Testing Framework](testing-framework.md) - Running tests in development environment
- [Debugging Tools](debugging-tools.md) - Development debugging and profiling
- [Code Generation](code-generation.md) - Generating client code during development
- [Docker Containerization](../infrastructure/docker-containerization.md) - Container architecture
- [Monitoring and Observability](../infrastructure/monitoring-observability.md) - Development observability