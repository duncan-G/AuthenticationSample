# Docker Containerization and Swarm Orchestration

## Overview

The authentication system uses Docker containers for application packaging and Docker Swarm for orchestration. This provides consistent deployment environments, service discovery, load balancing, and rolling updates across development and production environments.

## Implementation

### Docker Swarm Architecture

The system uses a Docker Swarm cluster with two node types:

#### Manager Nodes
- **Role**: Cluster orchestration and service management
- **Responsibilities**: 
  - Swarm initialization and cluster state management
  - Service scheduling and placement decisions
  - API endpoint for Docker commands
  - Raft consensus for high availability
- **Instance Type**: `t4g.small` (ARM64-based for cost efficiency)
- **Scaling**: 1-3 nodes (odd numbers for quorum)

#### Worker Nodes
- **Role**: Application container execution
- **Responsibilities**:
  - Run application containers and services
  - Report node status to managers
  - Execute tasks assigned by managers
- **Instance Types**: `t4g.small`, `m6g.medium` (mixed instance policy)
- **Scaling**: 1-6 nodes with auto-scaling based on CPU utilization

### Container Services

#### Core Application Services
```yaml
# Authentication microservice
auth-service:
  image: auth-sample/auth-grpc:latest
  ports:
    - "5001:5001"
  environment:
    - ASPNETCORE_ENVIRONMENT=Production
    - ConnectionStrings__DefaultConnection=...
  networks:
    - app-network

# Greeter microservice (example service)
greeter-service:
  image: auth-sample/greeter:latest
  ports:
    - "5002:5002"
  networks:
    - app-network
```

#### Infrastructure Services
```yaml
# Envoy API Gateway
envoy-proxy:
  image: envoyproxy/envoy:latest
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./envoy.yaml:/etc/envoy/envoy.yaml
  networks:
    - app-network

# OpenTelemetry Collector
otel-collector:
  image: otel/opentelemetry-collector-contrib:latest
  ports:
    - "4317:4317"  # gRPC
    - "4318:4318"  # HTTP
  volumes:
    - ./otel-collector.yaml:/etc/otel-collector-config.yaml
  networks:
    - app-network
```

### Network Configuration

#### Overlay Network
```bash
# Created automatically by manager bootstrap
docker network create \
  --driver overlay \
  --attachable \
  --subnet 10.20.0.0/16 \
  app-network
```

#### Service Discovery
- **Internal DNS**: Services communicate using service names
- **Load Balancing**: Built-in load balancing across service replicas
- **Health Checks**: Automatic health monitoring and failover

### Bootstrap Process

#### Manager Node Initialization

The manager bootstrap script (`userdata/manager.sh`) performs:

1. **System Setup**:
   ```bash
   # Install Docker and dependencies
   sudo dnf install -y docker jq awscli amazon-ecr-credential-helper
   sudo systemctl enable --now docker
   ```

2. **ECR Authentication**:
   ```bash
   # Configure ECR credential helper
   mkdir -p /root/.docker
   echo '{"credsStore":"ecr-login"}' > /root/.docker/config.json
   ```

3. **Swarm Initialization**:
   ```bash
   # Initialize Docker Swarm
   docker swarm init --advertise-addr $MANAGER_IP
   
   # Create overlay network
   docker network create --driver overlay --attachable app-network
   ```

4. **Parameter Store Integration**:
   ```bash
   # Store join tokens and network info in SSM
   aws ssm put-parameter --name /docker/swarm/worker-token --value $WORKER_TOKEN
   aws ssm put-parameter --name /docker/swarm/manager-ip --value $MANAGER_IP
   ```

#### Worker Node Joining

The worker bootstrap script (`userdata/worker.sh`) performs:

1. **System Setup**: Same Docker installation as manager
2. **Wait for Manager**: Poll SSM Parameter Store for join information
3. **Join Swarm**:
   ```bash
   # Retrieve join token and manager IP from SSM
   WORKER_TOKEN=$(aws ssm get-parameter --name /docker/swarm/worker-token --query 'Parameter.Value' --output text)
   MANAGER_IP=$(aws ssm get-parameter --name /docker/swarm/manager-ip --query 'Parameter.Value' --output text)
   
   # Join the swarm
   docker swarm join --token $WORKER_TOKEN $MANAGER_IP
   ```

### Service Deployment

#### Stack Deployment Files

Services are deployed using Docker Stack files:

```yaml
# PostgreSQL database stack
version: "3.8"
services:
  postgres:
    image: authentication-sample/postgres:latest
    environment:
      POSTGRES_DB: ${DATABASE_NAME}
      POSTGRES_USER: ${DATABASE_USER}
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD}
    ports:
      - "5432:5432"
    networks:
      - net
    volumes:
      - db_data:/var/lib/postgresql/data
    deploy:
      mode: global
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 3
```

#### Deployment Commands

```bash
# Deploy application stack
docker stack deploy -c docker-compose.yml auth-sample

# Deploy individual services
docker stack deploy -c postgres.stack.yaml postgres
docker stack deploy -c redis.stack.yaml redis
docker stack deploy -c otel-collector.stack.yaml monitoring
```

## Configuration

### Environment Variables

Services are configured through environment variables:

```bash
# Database configuration
DATABASE_NAME=authsample
DATABASE_USER=postgres
DATABASE_PASSWORD=secure_password

# Authentication service
ASPNETCORE_ENVIRONMENT=Production
JWT_ISSUER=https://auth.example.com
JWT_AUDIENCE=auth-sample-api

# AWS configuration
AWS_REGION=us-east-1
AWS_DEFAULT_REGION=us-east-1
```

### Volume Management

#### Persistent Volumes
```yaml
volumes:
  db_data:
    driver: local
  redis_data:
    driver: local
  logs:
    driver: local
```

#### Volume Mounting
```yaml
services:
  postgres:
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
```

### Resource Constraints

```yaml
deploy:
  resources:
    limits:
      cpus: '0.5'
      memory: 512M
    reservations:
      cpus: '0.25'
      memory: 256M
```

## Usage

### Development Environment

#### Local Docker Swarm Setup

1. **Initialize Swarm**:
   ```bash
   docker swarm init
   ```

2. **Create Network**:
   ```bash
   docker network create --driver overlay --attachable app-network
   ```

3. **Deploy Services**:
   ```bash
   # Start infrastructure services
   docker stack deploy -c infrastructure/postgres/postgres.stack.debug.yaml postgres
   docker stack deploy -c infrastructure/redis/redis.stack.debug.yaml redis
   
   # Start application services
   docker stack deploy -c docker-compose.yml auth-sample
   ```

#### Service Management

```bash
# List services
docker service ls

# View service logs
docker service logs auth-sample_auth-service

# Scale service
docker service scale auth-sample_auth-service=3

# Update service
docker service update --image auth-sample/auth-grpc:v2.0 auth-sample_auth-service
```

### Production Deployment

#### Automated Deployment

The production deployment is automated through the Terraform bootstrap process:

1. **Manager nodes** initialize the swarm and create the overlay network
2. **Worker nodes** join the swarm automatically using SSM Parameter Store
3. **Services** are deployed via CodeDeploy during the deployment process

#### Service Updates

```bash
# Rolling update with zero downtime
docker service update \
  --image auth-sample/auth-grpc:v2.0 \
  --update-parallelism 1 \
  --update-delay 30s \
  auth-sample_auth-service
```

#### Health Monitoring

```bash
# Check service health
docker service ps auth-sample_auth-service

# View node status
docker node ls

# Check swarm status
docker info | grep -A 10 "Swarm:"
```

## Testing

### Container Testing

1. **Image Building**:
   ```bash
   # Build application images
   docker build -t auth-sample/auth-grpc:latest microservices/Auth/
   docker build -t auth-sample/greeter:latest microservices/Greeter/
   ```

2. **Local Testing**:
   ```bash
   # Test individual containers
   docker run --rm -p 5001:5001 auth-sample/auth-grpc:latest
   
   # Test with environment variables
   docker run --rm -e ASPNETCORE_ENVIRONMENT=Development auth-sample/auth-grpc:latest
   ```

3. **Service Integration Testing**:
   ```bash
   # Deploy test stack
   docker stack deploy -c docker-compose.test.yml test-stack
   
   # Run integration tests
   docker run --rm --network app-network test-runner:latest
   ```

### Swarm Testing

1. **Cluster Health**:
   ```bash
   # Check all nodes are healthy
   docker node ls
   
   # Verify network connectivity
   docker network ls | grep overlay
   ```

2. **Service Discovery**:
   ```bash
   # Test service-to-service communication
   docker exec -it $(docker ps -q -f name=auth-service) ping greeter-service
   ```

3. **Load Balancing**:
   ```bash
   # Scale service and test load distribution
   docker service scale auth-sample_auth-service=3
   curl -H "Host: api.example.com" http://localhost/health
   ```

## Troubleshooting

### Common Issues

#### 1. Swarm Join Failures
```bash
# Check manager node status
docker node ls

# Verify SSM parameters
aws ssm get-parameter --name /docker/swarm/worker-token
aws ssm get-parameter --name /docker/swarm/manager-ip

# Check network connectivity
telnet $MANAGER_IP 2377
```

#### 2. Service Deployment Failures
```bash
# Check service status
docker service ps auth-sample_auth-service --no-trunc

# View service logs
docker service logs auth-sample_auth-service

# Check resource constraints
docker system df
docker system events
```

#### 3. Network Connectivity Issues
```bash
# List networks
docker network ls

# Inspect overlay network
docker network inspect app-network

# Test container connectivity
docker exec -it container_name nslookup service_name
```

#### 4. ECR Authentication Issues
```bash
# Test ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Check credential helper
docker-credential-ecr-login list
```

### Debugging Commands

```bash
# View detailed service information
docker service inspect auth-sample_auth-service

# Check container processes
docker exec -it container_name ps aux

# Monitor resource usage
docker stats

# View system events
docker system events --since 1h
```

### Log Analysis

```bash
# Service logs with timestamps
docker service logs -t auth-sample_auth-service

# Follow logs in real-time
docker service logs -f auth-sample_auth-service

# Filter logs by time
docker service logs --since 2023-01-01T00:00:00 auth-sample_auth-service
```

## Related Features

- [Terraform Infrastructure Deployment](terraform-deployment.md) - Infrastructure provisioning
- [AWS Deployment](aws-deployment.md) - Production deployment process
- [Monitoring and Observability](monitoring-observability.md) - Container monitoring
- [Load Balancing](load-balancing.md) - Traffic routing and SSL termination