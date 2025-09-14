# 🔐 Authentication Sample

A modern, production-ready authentication system built with microservices architecture. This sample demonstrates secure user authentication using .NET gRPC services, Next.js frontend, and enterprise-grade infrastructure components.

## 📚 Documentation

**👉 [View Complete Documentation](docs/README.md)**

### Quick Links
- **[🚀 Quick Start Guide](docs/guides/developer-setup.md)** - Get up and running in minutes
- **[🏛️ Architecture Overview](docs/guides/architecture-overview.md)** - System design and components  
- **[📋 Feature Index](docs/index.md)** - Complete feature documentation
- **[🔧 Troubleshooting](docs/guides/troubleshooting.md)** - Common issues and solutions

## ✨ Key Features

- **🔒 Secure Authentication**: JWT-based authentication with refresh tokens
- **🏗️ Microservices Architecture**: Scalable .NET gRPC services
- **🌐 Modern Frontend**: Next.js with TypeScript and Tailwind CSS
- **🔄 API Gateway**: Envoy proxy for routing and load balancing
- **📊 Observability**: Built-in monitoring with Aspire dashboard
- **🐳 Container Ready**: Full Docker support with Docker Swarm
- **📈 Production Ready**: Includes logging, monitoring, and health checks

## 🚀 Quick Start

### Prerequisites
- **Docker Desktop** with Docker Swarm enabled
- **.NET 9 SDK**
- **Node.js 22+** and npm

### 1. Setup & Start
```bash
# Clone and setup
git clone <repository-url>
cd AuthenticationSample

# Start everything
./setup.sh
./start.sh -a
```

### 2. Access the Application
- **Frontend**: https://localhost:3000
- **Aspire Dashboard**: http://localhost:18888

## 📖 What's Next?

For detailed setup instructions, feature documentation, deployment guides, and troubleshooting:

**👉 [Browse Complete Documentation](docs/README.md)**

### By Role
- **Developers**: [Developer Setup Guide](docs/guides/developer-setup.md)
- **DevOps**: [DevOps Deployment Guide](docs/guides/devops-deployment.md)  
- **Security**: [Security Features](docs/features/security/README.md)
- **Product**: [Architecture Overview](docs/guides/architecture-overview.md)
