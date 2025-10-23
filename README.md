# 🔐 Authentication Sample

A modern, production-ready authentication system built with microservices architecture. This sample demonstrates secure user authentication using .NET gRPC services, Next.js frontend, and enterprise-grade infrastructure components.

## 📚 Documentation

**👉 [View Complete Documentation](docs/README.md)**

### Quick Links
- **[🚀 Quick Start Guide](docs/guides/developer-setup.md)** - Get up and running in minutes
- **[🏛️ Architecture Overview](docs/guides/architecture-overview.md)** - System design and components  
- **[🔧 Troubleshooting](docs/guides/troubleshooting.md)** - Common issues and solutions

## ✨ Key Features

- **🔒 Secure Authentication**: JWT-based authentication with refresh tokens
- **🏗️ Microservices Architecture**: Scalable .NET gRPC services
- **🌐 Modern Frontend**: Next.js with TypeScript and Tailwind CSS
- **🔄 API Gateway**: Envoy proxy for routing and load balancing
- **📊 Observability**: Built-in monitoring
- **🐳 Container Ready**: Full Docker support with Docker Swarm
- **📈 Production Ready**: Includes logging, monitoring, and health checks

## 🚀 Quick Start

### Prerequisites
- **bash**
- **Docker**
- **.NET 9 SDK**
- **Node.js 22+** and npm
- **AWS cli** and AWS account with a **Hosted Zone**(doman) on Route53
- **Git & Github cli** with repo in github
- **Vercel** account with a API Key

### 1. AWS Setup (New AWS Account setup)
- Create an AWS SSO user group and profile with permissions listed in [setup-github-actions-oidc-policy.json](infrastructure/terraform/setup-github-actions-oidc-policy.json)
    - Configure sso profile `aws sso configure infra-setup`
    - This profile is used to provision dev resources in AWS
- Setup permissions required for run github actions to deploy AWS resources
    ```bash
    ./scripts/deployment/setup-infra-workflow.sh
    ```
- Go to github actions and run [infrastructure dev pipeline](.github/workflows/infrastructure-debug.yml) to setup cloud environment for dev
- Create an AWS SSO user group profile with permissions listed in [developer-policy.json](infrastructure/terraform/developer-policy.json)
    - Configure sso profile `aws sso configure developer`
    - This profile is used by applications to access AWS
    - *NOTE: There are variables in the JSON that need to be substituted with the real value*
- Setup dev secrets
    ```bash
    ./scripts/deployment/setup-secrets.sh
    ```

### 2. Local Setup & Start
```bash
# Setup dev secrets
# (If secrets are already setup in AWS Secret Manager by someone else, 
# still run this. It will store client secrets in .env.local)
./scripts/deployment/setup-secrets.sh

# Pull needed containers and run npm install
./setup.sh

# Start everything
./start.sh -a

# Restart a specific microservice
./restart <MicroserviceName>

# Start everything, but run applications in containers (prod-like)
./start.sh -A
```

##### Starting individual components
The start.sh script provides granular control over which components to start:
```bash
# Backend infrastructure (Docker Swarm, certificates)
./start.sh -b

# Similar to (-b) but alwys creates new certificates
./start.sh -B

# Databases (Redis, DynamoDB)
./start.sh -d

# Similar to (-d) but re-creates database volumes
./start.sh -D

# Microservices (local development)
./start.sh -m

# Similar to (-m) but all microservices are containerized
# Normally used for testing purposes
./start.sh -M

# API Gateway (Envoy proxy)
./start.sh -p

# Frontend application
./start.sh -c

# Frontend (when using containerized services)
./start.sh -C
```

##### Stop services
```bash
# This will entire backend, client and prune all volumes
./stop.sh

```

### 2. Access the Application
- **Frontend**: https://localhost:3000
- **Aspire Telemetry Dashboard**: http://localhost:18888
    - `logs` directory in root of application directory will also contain logs
- **Envoy Proxy Dashboard**: http://localhost:4000

## 📖 What's Next?

For detailed setup instructions, feature documentation, deployment guides, and troubleshooting:

**👉 [Browse Complete Documentation](docs/README.md)**

### By Role
- **Developers**: [Developer Setup Guide](docs/guides/developer-setup.md)
- **DevOps**: [DevOps Deployment Guide](docs/guides/devops-deployment.md)  
- **Security**: [Security Features](docs/features/security/README.md)
- **Product**: [Architecture Overview](docs/guides/architecture-overview.md)
