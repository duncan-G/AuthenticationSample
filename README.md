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
- **AWS cli** and AWS account with a **Domain** on Route53
- **Git & Github cli** with repo in github
- **Vercel** account with a API Key

### 1. AWS Setup (New repo setup)
- Create an AWS SSO user with permissions listed in  [setup-github-actions-oidc-poly.json](infrastructure/terraform/setup-github-actions-oidc-policy.json)
- Configure your sso profile `aws sso configure`
- Setup OIDC access for github to access AWS
    ```bash
    # Provides github actions ability to provision AWS resources via terraform
    ./scripts/deployment/setup-infra-workflow.sh

    # You can remove most resources by running the following (Read or run script to see what needs to be deleted manually)
    ./scripts/deployment/remove-infra-workflow.sh
    ```
- Setup Development secrets
    ```bash
    # Script will prompt you to manually enter secrets needed by the application. Client secrets will be stored in clients/auth-sample/.env.local while server secrets will be stored in AWS Secret Manager
    ./scripts/deployment/setup-secrets.sh
    ```

### 2. Local Setup & Start
```bash
# Start everything
./setup.sh
./start.sh -a

# Restart a specific microservice
./restart <MicroserviceName>

# Start everything, but run applications in containers
# Normally used for testing prod environment
./start.sh -A
```

##### Starting individual components
The start.sh script provides granular control over which components to start:
```bash
# Backend infrastructure (Docker Swarm, certificates)
./start.sh -b

# Similar to (-b) but creates new certificates
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
Stopping the Application

##### Stop services
```bash
# This will entire backend and prune all volumes
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
