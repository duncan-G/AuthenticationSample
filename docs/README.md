# Authentication System Documentation

Welcome to the documentation for the Authentication System - a modern, production-ready authentication platform built with microservices architecture.

## Quick Navigation

📋 **[Complete Navigation Index](navigation.md)** - Comprehensive navigation by role, technology, and workflow

### 📚 Features Documentation
- [Authentication Features](features/authentication/) - User signup, signin, verification, and session management
- [Security Features](features/security/) - Rate limiting, JWT validation, error handling, and CORS
- [Infrastructure Features](features/infrastructure/) - Terraform deployment, Docker containerization, and monitoring
- [Development Features](features/development/) - Local setup, testing, and debugging tools
- [API Features](features/api-gateway/) - gRPC services, protocol buffers, and client libraries

### 🚀 Getting Started Guides
- [Developer Setup Guide](guides/developer-setup.md) - Complete setup instructions for new developers
- [DevOps Deployment Guide](guides/devops-deployment.md) - Infrastructure deployment using Terraform
- [Architecture Overview](guides/architecture-overview.md) - System architecture and component interactions
- [Troubleshooting Guide](guides/troubleshooting.md) - Common issues and solutions

## System Overview

This authentication system demonstrates:
- **Secure Authentication**: JWT-based authentication with refresh tokens
- **Microservices Architecture**: Scalable .NET gRPC services with clean architecture patterns
- **Modern Frontend**: Next.js with TypeScript, React 19, and Tailwind CSS
- **API Gateway**: Envoy proxy for routing and load balancing
- **Observability**: Built-in monitoring with OpenTelemetry
- **Container Ready**: Full Docker support with Docker Swarm orchestration
- **Production Ready**: Includes logging, monitoring, health checks, and AWS deployment

## Technology Stack

- **Backend**: .NET 9.0, gRPC, ASP.NET Core
- **Frontend**: Next.js 15.3+, React 19, TypeScript 5, Tailwind CSS
- **Infrastructure**: Docker, Envoy Proxy, PostgreSQL, Redis, AWS
- **Observability**: OpenTelemetry, Aspire Dashboard (Dev), CloudWatch (Prd)

## Documentation Structure

This documentation is organized into two main sections:

1. **Features**: Detailed documentation of individual system features, organized by functional area
2. **Guides**: Step-by-step guides for setup, deployment, and maintenance tasks

Each feature document follows a consistent structure with overview, implementation details, configuration, usage instructions, testing guidance, and troubleshooting information.

---

*Last updated: $(date)*