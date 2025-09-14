# Developer Setup Guide

## Overview

This guide provides comprehensive step-by-step instructions for setting up the authentication system development environment. The system uses a microservices architecture with .NET gRPC services, Next.js frontend, and Docker-based infrastructure.

## Prerequisites

Before starting, ensure you have the following tools installed on your system:

### Required Software

#### 1. Docker Desktop
- **Version**: Latest stable version
- **Purpose**: Container orchestration and development environment
- **Installation**: Download from [docker.com](https://www.docker.com/products/docker-desktop/)
- **Configuration**: 
  - Enable Docker Swarm: `docker swarm init`
  - Allocate at least 4GB RAM to Docker
  - Enable file sharing for your project directory

#### 2. .NET SDK
- **Version**: .NET 9.0 or later
- **Purpose**: Building and running .NET microservices
- **Installation**: Download from [dotnet.microsoft.com](https://dotnet.microsoft.com/download)
- **Verification**: Run `dotnet --version` (should show 9.0.x)

#### 3. Node.js and npm
- **Version**: Node.js 22+ with npm
- **Purpose**: Frontend development and build tools
- **Installation**: Download from [nodejs.org](https://nodejs.org/) or use a version manager
- **Verification**: 
  - Run `node --version` (should show v22.x.x or higher)
  - Run `npm --version` (should show 10.x.x or higher)

#### 4. Bash Shell
- **Purpose**: Running development scripts
- **Windows**: Use Git Bash, WSL2, or PowerShell with bash compatibility
- **macOS/Linux**: Built-in bash shell
- **Verification**: Run `bash --version`

#### 5. Additional Tools
- **jq**: JSON processing tool
  - **Installation**: `brew install jq` (macOS) or download from [jqlang.github.io](https://jqlang.github.io/jq/)
  - **Purpose**: Processing JSON in setup scripts
- **AWS CLI** (optional, for production deployment):
  - **Installation**: Follow [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  - **Purpose**: Managing AWS resources and secrets

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd AuthenticationSample
```

### 2. Run Initial Setup

The setup script will pull required Docker images and install dependencies:

```bash
./setup.sh
```

This script performs the following actions:
- Cleans up Docker resources (containers, volumes, networks)
- Pulls required Docker images:
  - `mcr.microsoft.com/dotnet/aspire-dashboard:latest`
  - `envoyproxy/envoy:v1.34-latest`
  - `redis:latest`
  - `amazon/dynamodb-local:latest`
- Builds custom Docker images:
  - `protoc-gen-grpc-web:latest` (for gRPC code generation)
  - `auth-sample/postgres:latest` (PostgreSQL with custom configuration)
- Installs npm dependencies for the frontend client

## Environment Configuration

The system uses environment template files that need to be configured for your local development environment.

### Understanding Environment Templates

Environment template files (`.env.template`) serve as blueprints for creating actual environment files (`.env`). They contain:
- Required configuration keys
- Default values where applicable
- Comments explaining each setting

**Important**: Template files are used by the `setup-secrets.sh` script to create secrets in AWS Secrets Manager for production deployments.

### Environment Files Structure

```text
├── .env                                    # Root environment (created from infrastructure templates)
├── microservices/
│   ├── .env.template                      # Shared microservice settings
│   ├── .env.template.dev                  # Development-specific overrides
│   └── Auth/src/Auth.Grpc/
│       └── .env.template                  # Auth service specific settings
├── clients/auth-sample/
│   └── .env.local.template               # Frontend environment settings
└── infrastructure/
    ├── .env.template.dev                 # Development infrastructure settings
    └── .env.template.prod                # Production infrastructure settings
```

### Local Development Configuration

For local development, you need to create the following environment files:

#### 1. Root Environment File

The root `.env` file is already provided with development defaults:

```bash
# File: .env (already exists)
CERTIFICATE_PASSWORD=hgZIlPQbmNCcGcXeOgUMfNICxnuFG
ASPIRE_BROWSER_TOKEN=aspire
PGADMIN_DEFAULT_EMAIL=pgadmin@pgadmin.com
PGADMIN_DEFAULT_PASSWORD=pgadmin
DATABASE_NAME=postgres
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
```

#### 2. Frontend Environment File

Create the frontend environment file:

```bash
cp clients/auth-sample/.env.local.template clients/auth-sample/.env.local
```

Edit `clients/auth-sample/.env.local`:

```bash
# gRPC service endpoints (default values work for local development)
NEXT_PUBLIC_AUTHENTICATION_SERVICE_URL=http://localhost:11000/auth
NEXT_PUBLIC_GREETER_SERVICE_URL=https://localhost:11000/greet
NEXT_PUBLIC_OTLP_HTTP_ENDPOINT=http://localhost:11000/otlp/v1

# Disable TLS verification for local development
NODE_TLS_REJECT_UNAUTHORIZED=0
```

#### 3. Microservice Environment Files

For local development with microservices running outside containers, create:

```bash
# Shared microservice configuration
cp microservices/.env.template microservices/.env
cp microservices/.env.template.dev microservices/.env.dev

# Auth service specific configuration
cp microservices/Auth/src/Auth.Grpc/.env.template microservices/Auth/src/Auth.Grpc/.env
```

Edit the microservice environment files:

**microservices/.env:**
```bash
# OpenTelemetry endpoint for observability
Shared_ApplicationLogging__OtlpEndpoint=http://otel-collector_app:4317
Shared_ApplicationLogging__OtlpProtocol=grpc

# AWS Cognito settings (leave empty for local development)
Shared_Authentication__Audience=
Shared_Authentication__Authority=
```

**microservices/Auth/src/Auth.Grpc/.env:**
```bash
# AWS Cognito settings (leave empty for local development)
Auth_Cognito__ClientId=
Auth_Cognito__UserPoolId=
Auth_Cognito__Secret=
Auth_Cognito__RefreshTokenExpirationDays=30
```

### Production Environment Setup

For production deployment, use the `setup-secrets.sh` script to configure AWS Secrets Manager:

```bash
# Development secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile

# Production secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile -P
```

The script will:
1. Discover all `.env.template` files
2. Prompt you for values for each configuration key
3. Store backend secrets in AWS Secrets Manager
4. Create local `.env` files for frontend applications

## Starting the Application

### Option 1: Start Everything at Once

The simplest way to start the entire application:

```bash
./start.sh -a
```

This command starts all components in the correct order:
1. Backend infrastructure (Docker Swarm, certificates)
2. Database (PostgreSQL + PgAdmin)
3. Microservices (local development mode)
4. Frontend application

### Option 2: Start Components Individually

For more control or debugging, start components individually:

#### 1. Start Backend Infrastructure

```bash
./start.sh -b
```

This initializes:
- Docker Swarm (if not already initialized)
- SSL certificates for HTTPS
- Network configuration

#### 2. Start Database

```bash
./start.sh -d
```

This starts:
- PostgreSQL database (port 5432)
- PgAdmin web interface (port 5050)
- Redis cache
- OpenTelemetry collector
- Aspire dashboard (port 18888)

#### 3. Start Microservices

For local development (recommended):
```bash
./start.sh -m
```

For containerized microservices:
```bash
./start.sh -M
```

This starts:
- Authentication gRPC service (port 8000)
- Greeter gRPC service (port 8001)

#### 4. Start API Gateway (if using containers)

Only needed when running microservices in containers:
```bash
./start.sh -p
```

This starts:
- Envoy proxy (port 10000)

#### 5. Start Frontend

```bash
./start.sh -c
```

This starts:
- Next.js development server (port 3000)

### Accessing the Application

Once all components are running, you can access:

| Service | URL | Purpose |
|---------|-----|---------|
| **Frontend Application** | https://localhost:3000 | Main user interface |
| **API Gateway** | https://localhost:10000 | gRPC-Web endpoint (containers only) |
| **Direct gRPC Services** | http://localhost:11000 | gRPC-Web endpoint (local services) |
| **Aspire Dashboard** | http://localhost:18888 | Observability and monitoring |
| **PgAdmin** | http://localhost:5050 | Database administration |

### Default Credentials

- **PgAdmin**: 
  - Email: `pgadmin@pgadmin.com`
  - Password: `pgadmin`
- **Aspire Dashboard**: 
  - Token: `aspire` (automatically applied)

## Development Workflow

### Making Code Changes

#### Backend (.NET) Changes

1. **Microservice Changes**: The system uses hot reload, so changes to .NET code are automatically reflected
2. **Protocol Buffer Changes**: If you modify `.proto` files, regenerate code:
   ```bash
   # Regenerate gRPC client code
   ./scripts/development/gen-grpc-web.sh
   ```

#### Frontend (Next.js) Changes

1. **Component Changes**: Hot reload is enabled, changes appear immediately
2. **Environment Changes**: Restart the frontend after changing `.env.local`:
   ```bash
   # Stop and restart frontend
   ./stop.sh
   ./start.sh -c
   ```

### Running Tests

#### Backend Tests

```bash
# Run all .NET tests
dotnet test

# Run specific test project
dotnet test microservices/Auth/tests/Auth.UnitTests/
dotnet test microservices/Auth/tests/Auth.IntegrationTests/
```

#### Frontend Tests

```bash
cd clients/auth-sample

# Run unit tests
npm test

# Run tests in watch mode
npm test -- --watch

# Run integration tests
npm run test:integration
```

### Debugging

#### Backend Debugging

1. **Logs**: Check Aspire dashboard at http://localhost:18888
2. **Direct Debugging**: Attach debugger to running .NET processes
3. **Database**: Use PgAdmin at http://localhost:5050

#### Frontend Debugging

1. **Browser DevTools**: Standard React debugging
2. **Network Requests**: Monitor gRPC-Web calls in Network tab
3. **Console Logs**: Check browser console for errors

## Stopping the Application

### Stop All Services

```bash
./stop.sh
```

This stops all running services and containers.

### Stop Individual Components

```bash
# Stop specific services
docker service rm <service-name>

# Stop frontend (if running locally)
# Find and kill the Node.js process or use Ctrl+C in the terminal
```

## Common Setup Issues and Troubleshooting

### Docker Issues

#### Issue: "Docker daemon not running"
**Solution:**
```bash
# Start Docker Desktop
# On Linux, start Docker service:
sudo systemctl start docker
```

#### Issue: "Port already in use"
**Solution:**
```bash
# Find process using the port
lsof -i :3000  # Replace 3000 with the conflicting port
# Kill the process or change the port in configuration
```

#### Issue: "Docker Swarm not initialized"
**Solution:**
```bash
docker swarm init
```

### .NET Issues

#### Issue: ".NET SDK not found"
**Solution:**
```bash
# Verify .NET installation
dotnet --version
# If not installed, download from https://dotnet.microsoft.com/download
```

#### Issue: "Package restore failed"
**Solution:**
```bash
# Clear NuGet cache and restore
dotnet nuget locals all --clear
dotnet restore
```

### Node.js Issues

#### Issue: "Node version incompatible"
**Solution:**
```bash
# Check Node version
node --version
# Install Node 22+ from https://nodejs.org/
# Or use a version manager like nvm
```

#### Issue: "npm install fails"
**Solution:**
```bash
cd clients/auth-sample
# Clear npm cache
npm cache clean --force
# Delete node_modules and reinstall
rm -rf node_modules package-lock.json
npm install
```

### Environment Configuration Issues

#### Issue: "Environment variables not loaded"
**Solution:**
1. Verify `.env` files exist in correct locations
2. Check file permissions (should be readable)
3. Restart services after changing environment files
4. Verify no syntax errors in `.env` files (no spaces around `=`)

#### Issue: "gRPC connection failed"
**Solution:**
1. Verify microservices are running: `docker service ls`
2. Check if ports are accessible: `curl http://localhost:11000/health`
3. Verify environment URLs in frontend `.env.local`
4. Check firewall settings

### Database Issues

#### Issue: "Database connection failed"
**Solution:**
```bash
# Check if PostgreSQL is running
docker service ls | grep postgres
# Verify database credentials in .env file
# Check database logs in Aspire dashboard
```

#### Issue: "PgAdmin login failed"
**Solution:**
1. Use credentials from `.env` file:
   - Email: `pgadmin@pgadmin.com`
   - Password: `pgadmin`
2. If still failing, restart PgAdmin service

### SSL Certificate Issues

#### Issue: "SSL certificate errors in browser"
**Solution:**
1. Accept the self-signed certificate in browser
2. For Chrome: Click "Advanced" → "Proceed to localhost (unsafe)"
3. For production, use proper SSL certificates

#### Issue: "Certificate generation failed"
**Solution:**
```bash
# Regenerate certificates
./start.sh -B  # Capital B forces certificate regeneration
```

### Performance Issues

#### Issue: "Slow startup times"
**Solution:**
1. Increase Docker memory allocation (4GB minimum)
2. Close unnecessary applications
3. Use SSD storage for better I/O performance
4. Start components individually to identify bottlenecks

#### Issue: "High CPU usage"
**Solution:**
1. Check Docker resource limits
2. Monitor processes in Aspire dashboard
3. Reduce log verbosity in development

## Advanced Configuration

### Custom Ports

To change default ports, modify the following files:

1. **Frontend port**: `clients/auth-sample/package.json` (dev script)
2. **gRPC services**: `microservices/*/src/*/appsettings.Development.json`
3. **Database ports**: `infrastructure/postgres/postgres.stack.debug.yaml`

### Development vs Production Mode

The system supports different modes:

- **Development**: Local services, hot reload, detailed logging
- **Production**: Containerized services, optimized builds, AWS integration

Switch between modes using different start commands and environment files.

### Adding New Services

To add a new microservice:

1. Create service directory in `microservices/`
2. Follow the existing project structure
3. Add service to Docker Compose files
4. Update Envoy configuration for routing
5. Add environment templates

## Getting Help

### Documentation

- **Feature Documentation**: `docs/features/` - Detailed feature explanations
- **API Documentation**: Generated from Protocol Buffers
- **Infrastructure Documentation**: `docs/guides/` - Deployment and infrastructure guides

### Debugging Resources

- **Aspire Dashboard**: http://localhost:18888 - Comprehensive observability
- **Application Logs**: Available through Aspire dashboard
- **Database Admin**: http://localhost:5050 - Direct database access
- **gRPC Reflection**: Services support gRPC reflection for API exploration

### Common Commands Reference

```bash
# Setup and start
./setup.sh                    # Initial setup
./start.sh -a                 # Start everything
./stop.sh                     # Stop everything

# Individual components
./start.sh -b                 # Backend infrastructure
./start.sh -d                 # Database
./start.sh -m                 # Microservices (local)
./start.sh -M                 # Microservices (containers)
./start.sh -c                 # Frontend
./start.sh -p                 # Proxy (for containers)

# Development
dotnet build                  # Build .NET projects
dotnet test                   # Run .NET tests
npm test                      # Run frontend tests (from clients/auth-sample)

# Docker management
docker service ls             # List running services
docker service logs <name>   # View service logs
docker system prune          # Clean up Docker resources
```

This guide should get you up and running with the authentication system. If you encounter issues not covered here, check the troubleshooting section or refer to the specific feature documentation in the `docs/features/` directory.