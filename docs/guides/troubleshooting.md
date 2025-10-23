# Troubleshooting Guide

This guide provides solutions to common issues encountered when developing, deploying, and maintaining the authentication system.

## Table of Contents

- [Authentication Issues](#authentication-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [Development Issues](#development-issues)
- [Performance Issues](#performance-issues)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Backup and Recovery](#backup-and-recovery)

## Authentication Issues

### JWT Token Issues

#### Problem: "Invalid token" errors
**Symptoms:**
- Users getting logged out unexpectedly
- API calls returning 401 Unauthorized
- Token validation failures in logs

**Solutions:**
1. **Check token expiration:**
   ```bash
   # Decode JWT to check expiration
   echo "your-jwt-token" | cut -d. -f2 | base64 -d | jq .exp
   ```

2. **Verify JWT configuration:**
   ```bash
   # Check Auth service configuration
   docker logs auth-grpc-service | grep -i "jwt"
   ```

3. **Validate issuer and audience:**
   - Ensure `JWT_ISSUER` matches between services
   - Verify `JWT_AUDIENCE` is correctly configured
   - Check `JWT_SECRET_KEY` is consistent across services

#### Problem: Refresh token not working
**Symptoms:**
- Users can't refresh expired tokens
- "Refresh token invalid" errors
- Session expires prematurely

**Solutions:**
1. **Check refresh token storage:**
   ```bash
   # Verify Redis connection
   docker exec -it redis redis-cli ping
   
   # Check stored refresh tokens
   docker exec -it redis redis-cli keys "refresh_token:*"
   ```

2. **Validate refresh token configuration:**
   - Check `REFRESH_TOKEN_EXPIRY` setting
   - Verify Redis connection string
   - Ensure refresh token rotation is working

### Cognito Integration Issues

#### Problem: Cognito authentication failures
**Symptoms:**
- Sign-up/sign-in requests failing
- "User pool not found" errors
- AWS credential issues

**Solutions:**
1. **Verify AWS credentials:**
   ```bash
   # Check AWS credentials in container
   docker exec -it auth-grpc-service env | grep AWS
   
   # Test AWS connectivity
   aws cognito-idp list-user-pools --max-items 1
   ```

2. **Check Cognito configuration:**
   - Verify `COGNITO_USER_POOL_ID` is correct
   - Ensure `COGNITO_CLIENT_ID` matches your app client
   - Check AWS region configuration

#### Problem: Email verification not working
**Symptoms:**
- Verification emails not sent
- SES delivery failures
- Email bounce notifications

**Solutions:**
1. **Check SES configuration:**
   ```bash
   # Verify SES sending statistics
   aws ses get-send-statistics
   
   # Check SES reputation
   aws ses get-reputation
   ```

2. **Validate email templates:**
   - Check Cognito email templates
   - Verify SES domain verification
   - Test email delivery manually

## Infrastructure Issues

### Docker and Container Issues

#### Problem: Services not starting
**Symptoms:**
- Docker containers exiting immediately
- Port binding failures
- Service discovery issues

**Solutions:**
1. **Check container logs:**
   ```bash
   # View service logs
   docker service logs auth-grpc-service
   docker service logs envoy-proxy
   
   # Check container status
   docker service ps auth-grpc-service --no-trunc
   ```

2. **Verify port availability:**
   ```bash
   # Check port usage
   netstat -tulpn | grep :8080
   lsof -i :8080
   ```

3. **Inspect service configuration:**
   ```bash
   # Check service configuration
   docker service inspect auth-grpc-service
   
   # Verify network connectivity
   docker network ls
   docker network inspect auth-network
   ```

#### Problem: Database connection failures
**Symptoms:**
- "Connection refused" errors
- Database timeout issues
- Entity Framework migration failures

**Solutions:**
1. **Check PostgreSQL status:**
   ```bash
   # Verify PostgreSQL is running
   docker service ps postgres
   
   # Check database logs
   docker service logs postgres
   
   # Test connection
   docker exec -it postgres psql -U postgres -d authdb -c "SELECT 1;"
   ```

2. **Validate connection string:**
   ```bash
   # Check connection string format
   echo $DATABASE_CONNECTION_STRING
   
   # Test connectivity from application container
   docker exec -it auth-grpc-service nc -zv postgres 5432
   ```

### AWS Deployment Issues

#### Problem: Terraform deployment failures
**Symptoms:**
- Resource creation timeouts
- Permission denied errors
- State file conflicts

**Solutions:**
1. **Check AWS credentials and permissions:**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check IAM permissions
   aws iam simulate-principal-policy \
     --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
     --action-names ec2:CreateInstance \
     --resource-arns "*"
   ```

2. **Resolve Terraform state issues:**
   ```bash
   # Check Terraform state
   terraform state list
   
   # Refresh state
   terraform refresh
   
   # Import existing resources if needed
   terraform import aws_instance.example i-1234567890abcdef0
   ```

#### Problem: Load balancer health check failures
**Symptoms:**
- Services marked as unhealthy
- Traffic not routing to instances
- 502/503 errors from load balancer

**Solutions:**
1. **Check health check configuration:**
   ```bash
   # Verify health check endpoint
   curl -f http://your-instance:8080/health
   
   # Check security group rules
   aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
   ```

2. **Validate service health:**
   ```bash
   # Check application logs
   sudo journalctl -u your-service -f
   
   # Verify service is listening
   sudo netstat -tulpn | grep :8080
   ```

## Development Issues

### Local Setup Problems

#### Problem: Setup script failures
**Symptoms:**
- `./setup.sh` exits with errors
- Missing dependencies
- Permission issues

**Solutions:**
1. **Check prerequisites:**
   ```bash
   # Verify required tools
   docker --version
   dotnet --version
   node --version
   
   # Check Docker daemon
   docker info
   ```

2. **Fix permission issues:**
   ```bash
   # Fix script permissions
   chmod +x setup.sh start.sh stop.sh
   
   # Add user to docker group
   sudo usermod -aG docker $USER
   newgrp docker
   ```

#### Problem: gRPC code generation failures
**Symptoms:**
- Protobuf compilation errors
- Missing generated files
- Build failures after proto changes

**Solutions:**
1. **Regenerate gRPC code:**
   ```bash
   # Clean and regenerate
   ./scripts/development/gen-grpc-web.sh
   
   # Check protoc version
   protoc --version
   
   # Verify proto files syntax
   protoc --proto_path=. --dry_run your-file.proto
   ```

2. **Fix build issues:**
   ```bash
   # Clean build artifacts
   dotnet clean
   rm -rf clients/auth-sample/.next
   
   # Rebuild everything
   dotnet build
   npm run build
   ```

### Testing Issues

#### Problem: Integration tests failing
**Symptoms:**
- Database connection errors in tests
- Test containers not starting
- Flaky test results

**Solutions:**
1. **Check test environment:**
   ```bash
   # Verify test database
   docker ps | grep test
   
   # Check test configuration
   cat microservices/Auth/tests/Auth.IntegrationTests/appsettings.Testing.json
   ```

2. **Reset test environment:**
   ```bash
   # Clean test containers
   docker container prune -f
   
   # Restart test database
   docker-compose -f docker-compose.test.yml up -d postgres-test
   ```

## Performance Issues

### High CPU Usage

#### Problem: Services consuming excessive CPU
**Symptoms:**
- High CPU utilization
- Slow response times
- Service timeouts

**Solutions:**
1. **Identify CPU-intensive processes:**
   ```bash
   # Monitor CPU usage
   top -p $(pgrep -f "Auth.Grpc")
   
   # Check container resource usage
   docker stats
   ```

2. **Optimize application performance:**
   - Enable response caching
   - Optimize database queries
   - Implement connection pooling
   - Review logging levels

### Memory Issues

#### Problem: Memory leaks or high memory usage
**Symptoms:**
- Out of memory errors
- Gradual memory increase
- Container restarts

**Solutions:**
1. **Monitor memory usage:**
   ```bash
   # Check memory usage
   free -h
   docker stats --no-stream
   
   # Analyze .NET memory usage
   dotnet-dump collect -p $(pgrep -f "Auth.Grpc")
   ```

2. **Optimize memory usage:**
   - Review object disposal patterns
   - Implement proper caching strategies
   - Optimize Entity Framework queries
   - Configure garbage collection

### Database Performance

#### Problem: Slow database queries
**Symptoms:**
- High database response times
- Connection pool exhaustion
- Query timeouts

**Solutions:**
1. **Analyze query performance:**
   ```sql
   -- Check slow queries
   SELECT query, mean_time, calls 
   FROM pg_stat_statements 
   ORDER BY mean_time DESC 
   LIMIT 10;
   
   -- Check active connections
   SELECT count(*) FROM pg_stat_activity;
   ```

2. **Optimize database:**
   - Add appropriate indexes
   - Optimize query patterns
   - Configure connection pooling
   - Monitor connection usage

## Monitoring and Alerting

### Setting Up Monitoring

#### OpenTelemetry Configuration
```yaml
# otel-collector.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:

exporters:
  logging:
    loglevel: debug
  prometheus:
    endpoint: "0.0.0.0:8889"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

#### Key Metrics to Monitor
1. **Application Metrics:**
   - Request rate and latency
   - Error rates by endpoint
   - Authentication success/failure rates
   - JWT token validation metrics

2. **Infrastructure Metrics:**
   - CPU and memory usage
   - Disk I/O and space
   - Network throughput
   - Container health status

3. **Database Metrics:**
   - Connection pool usage
   - Query execution time
   - Lock wait time
   - Database size and growth

### Alerting Rules

#### Critical Alerts
```yaml
# Example Prometheus alerting rules
groups:
  - name: auth-system
    rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          
      - alert: DatabaseDown
        expr: up{job="postgres"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Database is down"
```

## Backup and Recovery

### Database Backup

#### Automated Backup Script
```bash
#!/bin/bash
# backup-database.sh

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="authdb"

# Create backup
docker exec postgres pg_dump -U postgres $DB_NAME > "$BACKUP_DIR/backup_${TIMESTAMP}.sql"

# Compress backup
gzip "$BACKUP_DIR/backup_${TIMESTAMP}.sql"

# Clean old backups (keep last 7 days)
find $BACKUP_DIR -name "backup_*.sql.gz" -mtime +7 -delete

echo "Backup completed: backup_${TIMESTAMP}.sql.gz"
```

#### Recovery Procedure
```bash
# Stop application services
docker service scale auth-grpc-service=0

# Restore database
gunzip -c backup_20240101_120000.sql.gz | docker exec -i postgres psql -U postgres -d authdb

# Restart services
docker service scale auth-grpc-service=1
```

### Configuration Backup

#### Backup Critical Configurations
```bash
#!/bin/bash
# backup-configs.sh

BACKUP_DIR="/config-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR/$TIMESTAMP"

# Backup configurations
cp -r infrastructure/terraform "$BACKUP_DIR/$TIMESTAMP/"
cp -r infrastructure/envoy "$BACKUP_DIR/$TIMESTAMP/"
cp docker-compose.yml "$BACKUP_DIR/$TIMESTAMP/"
cp .env.template "$BACKUP_DIR/$TIMESTAMP/"

# Create archive
tar -czf "$BACKUP_DIR/config_backup_${TIMESTAMP}.tar.gz" -C "$BACKUP_DIR" "$TIMESTAMP"
rm -rf "$BACKUP_DIR/$TIMESTAMP"

echo "Configuration backup completed: config_backup_${TIMESTAMP}.tar.gz"
```

### Disaster Recovery Plan

#### Recovery Steps
1. **Assess the situation:**
   - Identify affected components
   - Determine data loss scope
   - Estimate recovery time

2. **Infrastructure recovery:**
   ```bash
   # Redeploy infrastructure
   cd infrastructure/terraform
   terraform plan
   terraform apply
   ```

3. **Data recovery:**
   ```bash
   # Restore database from backup
   ./scripts/restore-database.sh backup_latest.sql.gz
   
   # Verify data integrity
   ./scripts/verify-data.sh
   ```

4. **Service recovery:**
   ```bash
   # Redeploy services
   docker stack deploy -c docker-compose.yml auth-sample
   
   # Verify service health
   ./scripts/health-check.sh
   ```

5. **Validation:**
   - Run integration tests
   - Verify authentication flows
   - Check monitoring dashboards
   - Validate user access

## Getting Help

### Log Analysis
```bash
# Centralized log viewing
docker service logs --follow auth-grpc-service

# Search for specific errors
docker service logs auth-grpc-service 2>&1 | grep -i error

# Export logs for analysis
docker service logs auth-grpc-service > auth-service.log
```

### Debug Mode
```bash
# Enable debug logging
export ASPNETCORE_ENVIRONMENT=Development
export Logging__LogLevel__Default=Debug

# Restart services with debug enabled
docker service update --env-add ASPNETCORE_ENVIRONMENT=Development auth-grpc-service
```

### Support Contacts
- **Development Issues:** Check GitHub issues and documentation
- **Infrastructure Issues:** Review AWS CloudWatch logs and metrics
- **Security Issues:** Follow security incident response procedures

Remember to always test solutions in a development environment before applying them to production.