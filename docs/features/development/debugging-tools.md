# Debugging Tools

## Overview

The debugging tools provide comprehensive development debugging, profiling, and diagnostic capabilities for the authentication system. The toolset includes the Aspire dashboard for service observability, gRPC debugging tools, frontend debugging integration, database inspection tools, and performance profiling utilities.

## Implementation

### Aspire Dashboard Integration

The Aspire dashboard provides centralized observability for all services:

```yaml
# aspire.stack.debug.yaml
services:
  aspire-dashboard:
    image: mcr.microsoft.com/dotnet/aspire-dashboard:latest
    ports:
      - "18888:18888"
    environment:
      - DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS=true
      - DOTNET_DASHBOARD_OTLP_ENDPOINT_URL=http://0.0.0.0:18889
    networks:
      - auth-sample-network
```

### OpenTelemetry Integration

Distributed tracing and metrics collection:

```typescript
// Frontend telemetry configuration
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
  traceExporter: new OTLPTraceExporter({
    url: 'http://localhost:4317/v1/traces',
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url: 'http://localhost:4317/v1/metrics',
    }),
  }),
})
```

### gRPC Debugging Tools

Specialized tools for gRPC service debugging:

```csharp
// gRPC service debugging configuration
public void ConfigureServices(IServiceCollection services)
{
    services.AddGrpc(options =>
    {
        options.EnableDetailedErrors = true;
        options.Interceptors.Add<LoggingInterceptor>();
        options.Interceptors.Add<ExceptionInterceptor>();
    });
}
```

### Database Debugging Integration

PgAdmin integration for database inspection:

```yaml
# Database debugging service
pgadmin:
  image: dpage/pgadmin4:latest
  ports:
    - "5050:80"
  environment:
    - PGADMIN_DEFAULT_EMAIL=admin@example.com
    - PGADMIN_DEFAULT_PASSWORD=admin
  volumes:
    - ./infrastructure/postgres/pg_admin/server.json:/pgadmin4/servers.json
```

## Configuration

### Development Debugging Setup

Enable debugging features in development environment:

```bash
# Environment variables for debugging
ASPNETCORE_ENVIRONMENT=Development
DOTNET_ENVIRONMENT=Development
ASPIRE_DASHBOARD_URL=http://localhost:18888
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# Frontend debugging
NEXT_PUBLIC_DEBUG_MODE=true
NODE_ENV=development
```

### Service-Specific Debug Configuration

#### .NET Service Debugging

```json
// appsettings.Development.json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Warning",
      "Grpc": "Debug"
    }
  },
  "OpenTelemetry": {
    "EnableConsoleExporter": true,
    "EnableDetailedTracing": true
  }
}
```

#### Frontend Debugging

```typescript
// next.config.ts
const nextConfig = {
  experimental: {
    instrumentationHook: true,
  },
  logging: {
    fetches: {
      fullUrl: true,
    },
  },
}
```

### IDE Integration

#### VS Code Configuration

```json
// .vscode/launch.json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Auth Service",
      "type": "coreclr",
      "request": "launch",
      "program": "${workspaceFolder}/microservices/Auth/src/Auth.Grpc/bin/Debug/net9.0/Auth.Grpc.dll",
      "args": [],
      "cwd": "${workspaceFolder}/microservices/Auth/src/Auth.Grpc",
      "env": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  ]
}
```

## Usage

### Aspire Dashboard

Access the Aspire dashboard for comprehensive service monitoring:

```bash
# Start services with debugging enabled
./start.sh -a

# Access dashboard
open http://localhost:18888
```

Dashboard features:
- **Service Map**: Visual representation of service dependencies
- **Distributed Tracing**: Request flow across services
- **Metrics**: Performance metrics and counters
- **Logs**: Centralized log aggregation
- **Health Checks**: Service health status monitoring

### gRPC Service Debugging

#### gRPC Client Testing

```bash
# Install grpcurl for command-line testing
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# List available services
grpcurl -plaintext localhost:5001 list

# Call a specific method
grpcurl -plaintext -d '{"email": "test@example.com"}' \
  localhost:5001 auth.SignUpService/InitiateSignUp
```

#### gRPC Reflection

Enable gRPC reflection for debugging:

```csharp
// Program.cs
if (app.Environment.IsDevelopment())
{
    app.MapGrpcReflectionService();
}
```

### Frontend Debugging

#### React DevTools Integration

```typescript
// Development-only debugging utilities
if (process.env.NODE_ENV === 'development') {
  // Enable React DevTools
  window.__REACT_DEVTOOLS_GLOBAL_HOOK__ = window.__REACT_DEVTOOLS_GLOBAL_HOOK__ || {}
  
  // Debug authentication state
  window.debugAuth = () => {
    console.log('Auth State:', useAuth())
  }
}
```

#### Network Request Debugging

```typescript
// gRPC request debugging
const debugGrpcCall = (serviceName: string, methodName: string, request: any) => {
  if (process.env.NODE_ENV === 'development') {
    console.group(`gRPC Call: ${serviceName}.${methodName}`)
    console.log('Request:', request)
    console.log('Timestamp:', new Date().toISOString())
    console.groupEnd()
  }
}
```

### Database Debugging

#### PgAdmin Interface

Access database debugging through PgAdmin:

```bash
# Access PgAdmin
open http://localhost:5050

# Login credentials
Email: admin@example.com
Password: admin
```

#### Direct Database Access

```bash
# Connect to PostgreSQL directly
docker exec -it $(docker ps -q -f name=postgres) psql -U postgres -d auth_sample

# Common debugging queries
SELECT * FROM users WHERE email = 'test@example.com';
SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 10;
EXPLAIN ANALYZE SELECT * FROM users WHERE email = $1;
```

### Performance Profiling

#### .NET Performance Profiling

```bash
# Install dotnet-trace
dotnet tool install --global dotnet-trace

# Collect performance trace
dotnet-trace collect --process-id <pid> --providers Microsoft-Extensions-Logging

# Analyze with PerfView or Visual Studio
```

#### Frontend Performance Debugging

```typescript
// Performance monitoring
if (process.env.NODE_ENV === 'development') {
  // Measure component render times
  const measureRender = (componentName: string) => {
    performance.mark(`${componentName}-start`)
    return () => {
      performance.mark(`${componentName}-end`)
      performance.measure(componentName, `${componentName}-start`, `${componentName}-end`)
    }
  }
}
```

### Log Analysis

#### Centralized Logging

```bash
# View service logs
docker service logs auth-sample_auth
docker service logs auth-sample_client

# Follow logs in real-time
docker service logs -f auth-sample_auth

# Filter logs by level
docker service logs auth-sample_auth | grep ERROR
```

#### Structured Log Queries

```bash
# Query logs with jq
docker service logs auth-sample_auth --no-trunc | \
  grep -E '^\{' | \
  jq 'select(.Level == "Error")'

# Extract specific fields
docker service logs auth-sample_auth --no-trunc | \
  grep -E '^\{' | \
  jq -r '.Timestamp + " " + .Message'
```

## Testing

### Debug Test Execution

#### Frontend Test Debugging

```bash
# Debug Jest tests
npm test -- --runInBand --verbose

# Debug specific test with Node debugger
node --inspect-brk node_modules/.bin/jest --runInBand signup-verification.test.tsx

# Use VS Code Jest extension for debugging
```

#### Backend Test Debugging

```bash
# Debug xUnit tests
dotnet test --logger "console;verbosity=detailed"

# Debug specific test in VS Code
# Set breakpoints and use "Debug Test" option
```

### Integration Test Debugging

```csharp
// Integration test with debugging
[Fact]
public async Task DebugAuthenticationFlow()
{
    // Enable detailed logging for this test
    var factory = new TestAuthWebApplicationFactory()
        .WithWebHostBuilder(builder =>
        {
            builder.ConfigureLogging(logging =>
            {
                logging.SetMinimumLevel(LogLevel.Debug);
            });
        });
    
    var client = factory.CreateGrpcClient<SignUpService.SignUpServiceClient>();
    
    // Test with debugging enabled
    var response = await client.InitiateSignUpAsync(new InitiateSignUpRequest
    {
        Email = "debug@example.com"
    });
    
    // Assertions with detailed output
    Assert.NotNull(response);
}
```

## Troubleshooting

### Common Debugging Issues

#### Aspire Dashboard Not Accessible

```bash
# Check if dashboard service is running
docker service ls | grep aspire

# Verify port binding
docker service inspect auth-sample_aspire-dashboard

# Check service logs
docker service logs auth-sample_aspire-dashboard
```

#### Missing Telemetry Data

```bash
# Verify OpenTelemetry configuration
curl http://localhost:4317/v1/traces

# Check OTEL collector status
docker service logs auth-sample_otel-collector

# Validate service instrumentation
grep -r "OpenTelemetry" microservices/Auth/src/
```

#### gRPC Debugging Issues

```bash
# Verify gRPC reflection is enabled
grpcurl -plaintext localhost:5001 list

# Check gRPC service health
grpcurl -plaintext localhost:5001 grpc.health.v1.Health/Check

# Validate proto definitions
protoc --decode_raw < request.bin
```

### Performance Debugging

#### Slow Request Investigation

1. **Check Aspire Dashboard**: Look for slow traces
2. **Analyze Database Queries**: Use PgAdmin query analyzer
3. **Profile .NET Code**: Use dotnet-trace or Visual Studio profiler
4. **Monitor Resource Usage**: Check Docker stats

#### Memory Leak Detection

```bash
# Monitor container memory usage
docker stats

# Generate .NET memory dump
dotnet-dump collect -p <process-id>

# Analyze with Visual Studio or dotMemory
```

#### Database Performance Issues

```sql
-- Enable query logging
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();

-- Analyze slow queries
SELECT query, mean_time, calls 
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;
```

### Development Workflow Debugging

#### Hot Reload Issues

```bash
# Frontend hot reload not working
rm -rf .next
npm run dev

# Backend hot reload issues
dotnet clean
dotnet build
dotnet watch run
```

#### Service Discovery Problems

```bash
# Check Docker network connectivity
docker network inspect auth-sample-network

# Verify service registration
docker service inspect auth-sample_auth

# Test inter-service communication
docker exec -it <container-id> curl http://auth:5001/health
```

## Related Features

- [Local Setup](local-setup.md) - Setting up the debugging environment
- [Testing Framework](testing-framework.md) - Debugging test failures
- [Monitoring and Observability](../infrastructure/monitoring-observability.md) - Production monitoring
- [Error Handling](../security/error-handling.md) - Debugging error scenarios
- [gRPC Services](../api/grpc-services.md) - gRPC service debugging