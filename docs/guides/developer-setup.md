# Developer Setup Guide

## Overview

This guide provides comprehensive step-by-step instructions for setting up the authentication system development environment. The system uses a microservices architecture with .NET gRPC services, Next.js frontend, and Docker-based infrastructure.

## Prerequisites

Before starting, ensure you have the following tools installed on your system:

### Required Software and Services

#### 1. Docker Desktop
- **Version**: Latest stable version
- **Purpose**: Container orchestration and development environment
- **Installation**: Download from [docker.com](https://www.docker.com/products/docker-desktop/)

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

#### 6. AWS Account and CLI
- **Account**: AWS account with a Route 53 hosted zone (domain)
- **CLI Installation**: Follow the [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Purpose**: Managing AWS resources and secrets; required by setup and deployment scripts
- **Verification**:
  - `aws --version`

#### 7. GitHub Account and CLI
- **Account**: GitHub account with access to the repository
- **Git Installation**: macOS `brew install git` (others: see [git-scm.com/downloads](https://git-scm.com/downloads))
- **GitHub CLI Installation**: macOS `brew install gh` (others: see [cli.github.com](https://cli.github.com))
- **Purpose**: Version control and CI/CD workflows
- **Verification**:
  - `git --version`
  - `gh --version`

#### 8. Vercel Account and API Key
- **Account**: Vercel account
- **API Token**: Create a Vercel API token for deployments
- **Purpose**: Hosting/deploying the frontend client. API key is stored in Github Secrets.
- **Docs**: See Vercel docs on creating an API token (`https://vercel.com/docs`)

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd AuthenticationSample
```

### 2. Run Initial Setup

The first time setting up this application, configure GitHub and AWS, then bootstrap the local environment.

#### 2.1 AWS Setup (New AWS Account setup)
- Create an AWS SSO user group and profile with permissions listed in [setup-github-actions-oidc-policy.json](../../infrastructure/terraform/setup-github-actions-oidc-policy.json)
  - Configure SSO profile `aws sso configure infra-setup`
  - This profile is used to provision dev resources in AWS
- Set up OIDC access for GitHub Actions to deploy AWS resources:
  ```bash
  ./scripts/deployment/setup-infra-workflow.sh

  # Optional: remove most of the provisioned resources
  ./scripts/deployment/remove-infra-workflow.sh
  ```
- In GitHub, run the Infrastructure Dev workflow to provision cloud resources for development
  - Workflow file: [infrastructure-dev.yml](../../.github/workflows/infrastructure-dev.yml)
- Create an AWS SSO user group and profile with permissions listed in [developer-policy.json](../../infrastructure/terraform/developer-policy.json)
  - Configure SSO profile `aws sso configure developer`
  - This profile is used by applications to access AWS
  - NOTE: There are variables in the JSON that need to be substituted with real values

#### 2.2 Set up secrets
Use the `setup-secrets.sh` script to configure secrets. This creates client `.env.local` files and stores backend secrets in AWS Secrets Manager.

For development and production:
```bash
# Development secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile <optional -f>

# Production secrets (stored in AWS Secrets Manager)
./scripts/deployment/setup-secrets.sh -a your-project-name -p your-aws-profile -P <optional -f>
```

The script will:
1. Discover all `.env.template` files
2. Prompt you for values for each configuration key
3. Store backend secrets in AWS Secrets Manager
4. Create local `.env` files for frontend applications
5. When re-run, only prompt for new secrets; use `-f` to overwrite all values

NOTE: It is recommended to manage production secrets in the AWS Console.

#### 2.3 Bootstrap local environment
The setup script pulls required Docker images and installs dependencies:
```bash
./setup.sh
```

This script performs the following actions:
- Cleans up Docker resources (containers, volumes, networks)
- Pulls required Docker images
- Builds custom Docker images
- Installs npm dependencies for the frontend client

## Environment Configuration

#### Understanding Environment Templates

Environment template files (`.env.template`) serve as blueprints for creating actual environment files (`.env`) and adding secrets to AWS Secret Manager. They contain:
- Required configuration keys
- Default values where applicable
- Comments explaining each setting
### Environment Files Structure

```text                                  # Root environment (created from 
├── microservices/
│   ├── .env.template                      # Shared microservice settings
│   ├── .env.template.dev                  # Development-specific overrides
│   └── <service-name>/**/
│       └── .env.template                  # Optional per-service settings
├── clients/
│   └── <client-name>/
│       └── .env.local.template            # Optional per-client settings
└── infrastructure/
    ├── .env.template.dev                 # Development infrastructure settings
    └── .env.template.prod                # Production infrastructure settings
```


For usage of `setup-secrets.sh` (including flags and behaviors), refer to section "2.2 Set up secrets".

## Starting the Application

*NOTE: start scripts are idempotent and safe to more than once as a way to restart environment components*

### Quick Start (summary)

```bash
# Start everything (first time)
./setup.sh
./start.sh -a

# Start everything, but run applications in containers (prod-like)
./start.sh -A

# Restart a specific microservice
./restart <MicroserviceName>
```

### Option 1: Start Everything at Once

The simplest way to start the entire application:

```bash
./start.sh -a
```

This command starts all components in the correct order:
1. Backend infrastructure (Docker Swarm, certificates)
2. Database (Redis, DynamoDB)
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
- Aspire dashboard (port 18888)

To force regeneration of certificates:
```bash
./start.sh -B
```

#### 2. Start Databases

```bash
./start.sh -d
```

This starts:
- Redis cache
- Dynamo DB

To recreate database volumes:
```bash
./start.sh -D
```

#### 3. Start Microservices

For local development (recommended):
```bash
./start.sh -m
```

For containerized microservices:
```bash
./start.sh -M
```


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

Frontend when using containerized services:
```bash
./start.sh -C
```

## Stopping the Application

### Stop All Services

```bash
./stop.sh
```

This stops all running services and containers and prunes related Docker volumes.

### Stop Individual Components

```bash
# Stop specific services
docker service rm <service-name>

# Stop frontend
# Find and kill the Node.js process (pid located in pids directory in root of project) or use Ctrl+C in the terminal that was opened when the client started

# You can also run the following script
./scripts/development/stop_client.sh
```

### Accessing the Application

Once all components are running, you can access:

| Service | URL | Purpose |
|---------|-----|---------|
| **Frontend Application** | https://localhost:3000 | Main user interface |
| **API Gateway** | https://localhost:4000 | gRPC-Web endpoint (containers only) |
| **Direct gRPC Services** | http://localhost:11000 | gRPC-Web endpoint (local services) |
| **Aspire Dashboard** | http://localhost:18888 | Observability and monitoring |


## Development Workflow

### Making Code Changes

#### Backend (.NET) Changes

1. **Microservice Changes**: The system uses hot reload, so changes to .NET code are automatically reflected. However, the donet watcher may at times require you to rebuild an application. Use the `restart.sh` script to do so.
2. **Protocol Buffer Changes**: If you modify `.proto` files, regenerate code:
   ```bash
   # Regenerate gRPC client code
   ./scripts/development/gen-grpc-web.sh
   ```

#### Frontend (Next.js) Changes

1. **Component Changes**: Hot reload is enabled, changes appear immediately
2. **Environment Changes**: Restart the frontend after changing `.env.local`:


### Debugging

#### Backend Debugging

1. **Logs**: Check Aspire dashboard at http://localhost:18888
2. **Log Files**: Check `logs` directoy in root of application
3. **Direct Debugging**: Attach debugger to running .NET processes

#### Frontend Debugging

1. **Browser DevTools**: Standard React debugging
2. **Network Requests**: Monitor gRPC-Web calls in Network tab
3. **Console Logs**: Check browser console for errors
4. **Logs** Check Aspire dashboard at http://localhost:18888
