# 🔐 Authentication Sample Application

A modern, production-ready authentication system built with microservices architecture. This sample demonstrates secure user authentication using .NET gRPC services, Next.js frontend, and enterprise-grade infrastructure components.

## ✨ Features

- **🔒 Secure Authentication**: JWT-based authentication with refresh tokens
- **🏗️ Microservices Architecture**: Scalable .NET gRPC services
- **🌐 Modern Frontend**: Next.js with TypeScript and Tailwind CSS
- **🔄 API Gateway**: Envoy proxy for routing and load balancing
- **📊 Observability**: Built-in monitoring with Aspire dashboard
- **🐳 Container Ready**: Full Docker support with Docker Swarm
- **🔐 TLS/SSL**: Automatic certificate generation and management
- **📈 Production Ready**: Includes logging, monitoring, and health checks

## 🔒 Security Notes

- All `.env` and `.env.docker` files are git-ignored
- `.env.template` files are committed to the repository
- Never commit sensitive values in environment files
- Use strong, unique passwords for each environment

## 🚀 Quick Start

### Prerequisites

- **Docker Desktop** with Docker Swarm enabled
- **.NET 9 SDK**
- **Node.js 22+** and npm
- **bash** shell

### 1. Clone and Setup

```bash
git clone <repository-url>
cd AuthenticationSample
```

### 2. Environment Configuration

```bash
# Copy and configure environment files
cp .env.template .env
cp Microservices/Authentication/src/Authentication.Grpc/.env.template Microservices/Authentication/src/Authentication.Grpc/.env
cp Microservices/Authentication/src/Authentication.Grpc/.env.docker.template Microservices/Authentication/src/Authentication.Grpc/.env.docker
cp Clients/authentication-sample/.env.docker.template Clients/authentication-sample/.env.docker

# Edit all .env files with your configuration values
```

**Note:** The `.env.docker` files are only needed when running microservices in containers with `./start.sh -M`

### 3. Start Everything

```bash
# Start all components in one command
./start.sh -a
```

### 4. Access the Application

- **Frontend**: https://localhost:3000
- **API Gateway**: https://localhost:10000
- **Aspire Dashboard**: http://localhost:18888
- **PgAdmin**: http://localhost:5050

## 📖 Detailed Usage

### Starting Individual Components

The `start.sh` script provides granular control over which components to start:

```bash
# Backend infrastructure (Docker Swarm, certificates)
./start.sh -b

# Similar to (-b) but creates new certificates
./start.sh -B

# Database (PostgreSQL + PgAdmin)
./start.sh -d

# Similar to (-d) but re-creates database volume
./start.sh -D

# Microservices (local development)
./start.sh -m

# Microservices (containerized)
./start.sh -M

# API Gateway (Envoy proxy) Only needed when using containers
./start.sh -p

# Frontend application
./start.sh -c

# Frontend (when using containerized services)
./start.sh -C
```

### Stopping the Application

```bash
# Stop all services
./stop.sh
```

### Components

| Component | Technology | Purpose | Port |
|-----------|------------|---------|------|
| **Frontend** | Next.js + TypeScript | User interface | 3000 |
| **API Gateway** | Envoy Proxy | Routing & load balancing | 10000 |
| **Authentication Service** | .NET gRPC | User authentication | 8000 |
| **Database** | PostgreSQL | Data persistence | 5432 |
| **Admin UI** | PgAdmin | Database management | 5050 |
| **Monitoring** | Aspire Dashboard | Observability | 18888 |
