# Monitoring and Observability with OpenTelemetry and Aspire Dashboard

## Overview

The authentication system implements comprehensive monitoring and observability using OpenTelemetry for distributed tracing and metrics collection, combined with the Aspire Dashboard for development-time observability. This provides end-to-end visibility into application performance, distributed request flows, and system health.

## Implementation

### OpenTelemetry Architecture

#### Components Overview
- **OpenTelemetry Collector**: Centralized telemetry data processing and export
- **Instrumentation Libraries**: Automatic and manual instrumentation for .NET and JavaScript
- **Exporters**: Send telemetry data to AWS CloudWatch, X-Ray, and development dashboards
- **Aspire Dashboard**: Development-time observability and debugging interface

#### Data Types Collected
1. **Traces**: Distributed request flows across microservices
2. **Metrics**: Application and infrastructure performance metrics
3. **Logs**: Structured application logs with correlation IDs

### OpenTelemetry Collector Configuration

The collector is configured to receive, process, and export telemetry data:

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
  memory_limiter:
    limit_mib: 900
    check_interval: 5s
    spike_limit_mib: 150
    
  resource:
    attributes:
      - key: service.name
        action: upsert
        from_attribute: service.name
      - key: service.version
        action: upsert
        from_attribute: service.version

  batch:
    timeout: 10s
    send_batch_max_size: 5000

exporters:
  awsxray:
    region: ${AWS_REGION}
    no_verify_ssl: false
    
  awsemf:
    region: ${AWS_REGION}
    namespace: AuthenticationSample/OpenTelemetry
    dimension_rollup_option: NoDimensionRollup
    
  awscloudwatchlogs:
    region: ${AWS_REGION}
    log_group_name: /aws/otel/application-logs
    log_stream_name: otel-collector

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [awsxray]
      
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [awsemf]
      
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [awscloudwatchlogs]
```

### .NET Service Instrumentation

#### Automatic Instrumentation

Services are automatically instrumented using OpenTelemetry .NET libraries:

```csharp
// Program.cs - Auth.Grpc service
var builder = WebApplication.CreateBuilder(args);

// Add OpenTelemetry
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddGrpcClientInstrumentation()
        .AddGrpcCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://otel-collector:4317");
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://otel-collector:4317");
        }));

// Add logging
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("http://otel-collector:4318");
    });
});
```

#### Custom Instrumentation

Custom spans and metrics for business logic:

```csharp
// Custom activity source for business operations
private static readonly ActivitySource ActivitySource = new("AuthSample.Auth");

public async Task<SignUpResponse> SignUpAsync(SignUpRequest request)
{
    using var activity = ActivitySource.StartActivity("SignUp");
    activity?.SetTag("user.email", request.Email);
    activity?.SetTag("signup.method", request.Method);
    
    try
    {
        // Business logic
        var result = await _identityService.SignUpAsync(request);
        
        activity?.SetTag("signup.success", true);
        activity?.SetStatus(ActivityStatusCode.Ok);
        
        return result;
    }
    catch (Exception ex)
    {
        activity?.SetTag("signup.success", false);
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
        throw;
    }
}
```

### Frontend Instrumentation

#### Next.js Application Monitoring

```typescript
// instrumentation.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-otlp-http';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-collector:4318/v1/traces',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
```

#### Browser Instrumentation

```typescript
// telemetry.ts
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { getWebAutoInstrumentations } from '@opentelemetry/auto-instrumentations-web';
import { OTLPTraceExporter } from '@opentelemetry/exporter-otlp-http';

const provider = new WebTracerProvider();

provider.addSpanProcessor(
  new BatchSpanProcessor(
    new OTLPTraceExporter({
      url: '/api/traces', // Proxied to collector
    })
  )
);

provider.register();
```

### Aspire Dashboard Integration

#### Development Configuration

The Aspire Dashboard provides a unified view of all telemetry data during development:

```yaml
# aspire.stack.debug.yaml
version: "3.8"
services:
  aspire-dashboard:
    image: mcr.microsoft.com/dotnet/aspire-dashboard:latest
    ports:
      - "18888:18888"
    environment:
      - DOTNET_DASHBOARD_OTLP_ENDPOINT_URL=http://otel-collector:4317
      - DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS=true
    networks:
      - net
    deploy:
      mode: global
```

#### Dashboard Features

1. **Distributed Tracing**: Visual representation of request flows
2. **Metrics Dashboard**: Real-time performance metrics
3. **Log Correlation**: Logs correlated with traces and spans
4. **Resource Monitoring**: Service health and resource usage
5. **Dependency Mapping**: Service-to-service communication visualization

### AWS CloudWatch Integration

#### Metrics Export

Custom metrics are exported to CloudWatch with proper namespacing:

```yaml
# CloudWatch metrics configuration
awsemf:
  region: ${AWS_REGION}
  namespace: AuthenticationSample/OpenTelemetry
  dimension_rollup_option: NoDimensionRollup
  metric_declarations:
    - dimensions: [[service.name], [service.name, service.version]]
      metric_name_selectors: [".*"]
```

#### Log Aggregation

Application logs are centralized in CloudWatch:

```yaml
# CloudWatch logs configuration
awscloudwatchlogs:
  region: ${AWS_REGION}
  log_group_name: /aws/otel/application-logs
  log_stream_name: otel-collector
  sending_queue:
    enabled: true
    queue_size: 2048
  retry_on_failure:
    enabled: true
    initial_interval: 5s
    max_interval: 1m
    max_elapsed_time: 10m
```

#### X-Ray Tracing

Distributed traces are sent to AWS X-Ray for production monitoring:

```yaml
# X-Ray exporter configuration
awsxray:
  region: ${AWS_REGION}
  no_verify_ssl: false
```

## Configuration

### Environment Variables

```bash
# OpenTelemetry configuration
export OTEL_SERVICE_NAME="auth-service"
export OTEL_SERVICE_VERSION="1.0.0"
export OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector:4317"
export OTEL_RESOURCE_ATTRIBUTES="service.name=auth-service,service.version=1.0.0"

# AWS configuration for exporters
export AWS_REGION="us-east-1"
export AWS_DEFAULT_REGION="us-east-1"

# Aspire Dashboard
export DOTNET_DASHBOARD_OTLP_ENDPOINT_URL="http://otel-collector:4317"
export DOTNET_DASHBOARD_UNSECURED_ALLOW_ANONYMOUS="true"
```

### Service Configuration

#### .NET Service Configuration

```json
{
  "OpenTelemetry": {
    "ServiceName": "auth-service",
    "ServiceVersion": "1.0.0",
    "Exporters": {
      "Otlp": {
        "Endpoint": "http://otel-collector:4317"
      }
    },
    "Tracing": {
      "IncludeFormattedMessage": true,
      "IncludeScopes": true
    }
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "OpenTelemetry": "Warning"
    }
  }
}
```

#### Collector Resource Configuration

```yaml
# Resource processor configuration
resource:
  attributes:
    - key: service.name
      action: upsert
      from_attribute: service.name
    - key: service.version
      action: upsert
      from_attribute: service.version
    - key: deployment.environment
      value: ${ENVIRONMENT}
      action: upsert
    - key: cloud.provider
      value: aws
      action: upsert
    - key: cloud.region
      value: ${AWS_REGION}
      action: upsert
```

## Usage

### Development Environment

#### Starting Monitoring Stack

1. **Start OpenTelemetry Collector**:
   ```bash
   docker stack deploy -c infrastructure/otel-collector/otel-collector.stack.debug.yaml monitoring
   ```

2. **Start Aspire Dashboard**:
   ```bash
   docker stack deploy -c infrastructure/otel-collector/aspire.stack.debug.yaml aspire
   ```

3. **Access Dashboard**:
   ```bash
   # Open Aspire Dashboard
   open http://localhost:18888
   ```

#### Viewing Telemetry Data

1. **Distributed Traces**:
   - Navigate to "Traces" tab in Aspire Dashboard
   - Filter by service name or operation
   - Click on traces to view detailed span information

2. **Metrics**:
   - View real-time metrics in "Metrics" tab
   - Monitor HTTP request rates, response times, and error rates
   - Track custom business metrics

3. **Logs**:
   - Correlated logs appear in "Logs" tab
   - Filter by trace ID to see all logs for a request
   - Search by log level or message content

### Production Monitoring

#### CloudWatch Dashboards

Create custom dashboards for production monitoring:

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AuthenticationSample/OpenTelemetry", "http.server.duration", "service.name", "auth-service"],
          [".", "http.server.request.count", ".", "."],
          [".", "http.server.error.count", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Auth Service Performance"
      }
    }
  ]
}
```

#### X-Ray Service Map

View service dependencies and performance:

```bash
# View X-Ray service map
aws xray get-service-graph --start-time 2023-01-01T00:00:00Z --end-time 2023-01-01T01:00:00Z
```

#### CloudWatch Alarms

Set up alerts for critical metrics:

```bash
# Create high error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "AuthService-HighErrorRate" \
  --alarm-description "Auth service error rate is high" \
  --metric-name "http.server.error.count" \
  --namespace "AuthenticationSample/OpenTelemetry" \
  --statistic "Sum" \
  --period 300 \
  --threshold 10 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 2
```

## Testing

### Telemetry Testing

1. **Trace Validation**:
   ```bash
   # Generate test traffic
   curl -H "Authorization: Bearer $JWT_TOKEN" https://api.example.com/auth/signup
   
   # Verify traces in Aspire Dashboard
   # Check for complete trace spans and proper correlation
   ```

2. **Metrics Verification**:
   ```bash
   # Check metrics endpoint
   curl http://localhost:9090/metrics
   
   # Verify metrics in CloudWatch
   aws cloudwatch get-metric-statistics \
     --namespace "AuthenticationSample/OpenTelemetry" \
     --metric-name "http.server.duration"
   ```

3. **Log Correlation**:
   ```bash
   # Check log correlation with trace IDs
   aws logs filter-log-events \
     --log-group-name "/aws/otel/application-logs" \
     --filter-pattern "{ $.traceId = \"abc123\" }"
   ```

### Performance Testing

1. **Load Testing with Monitoring**:
   ```bash
   # Run load test while monitoring
   k6 run --vus 10 --duration 30s load-test.js
   
   # Monitor metrics in real-time
   watch -n 1 'curl -s http://localhost:9090/metrics | grep http_requests_total'
   ```

2. **Distributed Trace Analysis**:
   ```bash
   # Analyze trace performance
   # Look for slow spans, high latency services
   # Identify bottlenecks in service communication
   ```

## Troubleshooting

### Common Issues

#### 1. Missing Traces

```bash
# Check collector connectivity
curl -v http://otel-collector:4317

# Verify service instrumentation
docker logs auth-service | grep -i "opentelemetry"

# Check collector logs
docker service logs monitoring_otel-collector
```

#### 2. High Memory Usage

```bash
# Check collector memory usage
docker stats monitoring_otel-collector

# Adjust memory limiter configuration
# Reduce batch size or increase memory limits
```

#### 3. Export Failures

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify CloudWatch permissions
aws logs describe-log-groups --log-group-name-prefix "/aws/otel"

# Check X-Ray service
aws xray get-service-graph --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)
```

#### 4. Dashboard Connectivity

```bash
# Check Aspire Dashboard status
curl -I http://localhost:18888

# Verify collector endpoint configuration
docker exec -it aspire-dashboard env | grep OTLP
```

### Debugging Commands

```bash
# View collector configuration
docker exec -it otel-collector cat /etc/otel-collector-config.yaml

# Check service instrumentation
docker exec -it auth-service dotnet --list-runtimes

# Monitor telemetry flow
docker service logs -f monitoring_otel-collector

# Test OTLP endpoint
grpcurl -plaintext otel-collector:4317 list
```

### Performance Optimization

```bash
# Optimize collector performance
# Adjust batch processor settings
batch:
  timeout: 5s
  send_batch_max_size: 1000
  send_batch_size: 500

# Tune memory limiter
memory_limiter:
  limit_mib: 512
  check_interval: 1s
  spike_limit_mib: 100
```

## Related Features

- [Docker Containerization](docker-containerization.md) - Container orchestration and service deployment
- [AWS Deployment](aws-deployment.md) - Production infrastructure and CloudWatch integration
- [Load Balancing](load-balancing.md) - Traffic routing and health checks
- [Database Setup](database-setup.md) - Database monitoring and performance metrics