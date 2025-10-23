# Monitoring and Alerting Setup Guide

This guide provides detailed instructions for setting up comprehensive monitoring and alerting for the authentication system in production environments.

## Table of Contents

- [Overview](#overview)
- [Monitoring Stack](#monitoring-stack)
- [Metrics Collection](#metrics-collection)
- [Alerting Rules](#alerting-rules)
- [Dashboard Configuration](#dashboard-configuration)
- [Log Management](#log-management)
- [Health Checks](#health-checks)

## Overview

The monitoring and alerting system provides:
- Real-time system health monitoring
- Performance metrics collection
- Automated alerting for critical issues
- Centralized log management
- Custom dashboards for different stakeholders

### Architecture

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │───▶│   Prometheus    │───▶│    Grafana      │
│   (Metrics)     │    │   (Collection)  │    │  (Visualization)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │   AlertManager  │
                       │   (Alerting)    │
                       └─────────────────┘
```

## Monitoring Stack

### Prometheus Configuration

#### prometheus.yml
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'auth-system'
    environment: 'production'

rule_files:
  - "alert_rules.yml"
  - "recording_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Application metrics
  - job_name: 'auth-services'
    static_configs:
      - targets: 
        - 'auth-grpc-service:8080'
        - 'greeter-service:8080'
    metrics_path: /metrics
    scrape_interval: 10s
    scrape_timeout: 5s

  # Database metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
    scrape_interval: 15s

  # Redis metrics
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
    scrape_interval: 15s

  # Infrastructure metrics
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 15s

  # Load balancer metrics
  - job_name: 'envoy'
    static_configs:
      - targets: ['envoy:9901']
    metrics_path: /stats/prometheus
    scrape_interval: 15s
```

### AlertManager Configuration

#### alertmanager.yml
```yaml
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@your-domain.com'
  smtp_auth_username: 'alerts@your-domain.com'
  smtp_auth_password: 'your-password'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'
  routes:
  - match:
      severity: critical
    receiver: 'critical-alerts'
    group_wait: 5s
    repeat_interval: 5m
  - match:
      severity: warning
    receiver: 'warning-alerts'
    repeat_interval: 30m

receivers:
- name: 'web.hook'
  webhook_configs:
  - url: 'http://127.0.0.1:5001/'

- name: 'critical-alerts'
  email_configs:
  - to: 'oncall@your-domain.com'
    subject: 'CRITICAL: {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      Labels: {{ range .Labels.SortedPairs }}{{ .Name }}={{ .Value }} {{ end }}
      {{ end }}
  slack_configs:
  - api_url: 'YOUR_SLACK_WEBHOOK_URL'
    channel: '#critical-alerts'
    title: 'Critical Alert: {{ .GroupLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

- name: 'warning-alerts'
  email_configs:
  - to: 'team@your-domain.com'
    subject: 'WARNING: {{ .GroupLabels.alertname }}'
    body: |
      {{ range .Alerts }}
      Alert: {{ .Annotations.summary }}
      Description: {{ .Annotations.description }}
      {{ end }}

inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['alertname', 'cluster', 'service']
```

## Metrics Collection

### Application Metrics

#### .NET Service Metrics
```csharp
// Program.cs - Add metrics collection
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

// Add Prometheus metrics
builder.Services.AddSingleton<IMetricsLogger, MetricsLogger>();

var app = builder.Build();

// Enable metrics endpoint
app.UseRouting();
app.UseHttpMetrics(); // Collect HTTP metrics
app.MapMetrics(); // Expose /metrics endpoint

// Custom metrics middleware
app.Use(async (context, next) =>
{
    using var activity = Activity.StartActivity("http_request");
    var stopwatch = Stopwatch.StartNew();
    
    try
    {
        await next();
    }
    finally
    {
        stopwatch.Stop();
        
        // Record custom metrics
        var metricsLogger = context.RequestServices.GetService<IMetricsLogger>();
        metricsLogger?.RecordRequestDuration(
            context.Request.Method,
            context.Request.Path,
            context.Response.StatusCode,
            stopwatch.ElapsedMilliseconds);
    }
});
```

#### Custom Metrics Implementation
```csharp
public interface IMetricsLogger
{
    void RecordRequestDuration(string method, string path, int statusCode, long durationMs);
    void RecordAuthenticationAttempt(bool success, string method);
    void RecordDatabaseOperation(string operation, long durationMs, bool success);
}

public class MetricsLogger : IMetricsLogger
{
    private static readonly Counter AuthAttempts = Metrics
        .CreateCounter("auth_attempts_total", "Total authentication attempts", 
            new[] { "method", "result" });

    private static readonly Histogram RequestDuration = Metrics
        .CreateHistogram("http_request_duration_seconds", "HTTP request duration",
            new[] { "method", "path", "status_code" });

    private static readonly Histogram DatabaseOperationDuration = Metrics
        .CreateHistogram("database_operation_duration_seconds", "Database operation duration",
            new[] { "operation", "result" });

    private static readonly Gauge ActiveSessions = Metrics
        .CreateGauge("active_sessions_total", "Number of active user sessions");

    public void RecordRequestDuration(string method, string path, int statusCode, long durationMs)
    {
        RequestDuration
            .WithLabels(method, path, statusCode.ToString())
            .Observe(durationMs / 1000.0);
    }

    public void RecordAuthenticationAttempt(bool success, string method)
    {
        AuthAttempts
            .WithLabels(method, success ? "success" : "failure")
            .Inc();
    }

    public void RecordDatabaseOperation(string operation, long durationMs, bool success)
    {
        DatabaseOperationDuration
            .WithLabels(operation, success ? "success" : "failure")
            .Observe(durationMs / 1000.0);
    }
}
```

### Infrastructure Metrics

#### Docker Compose for Monitoring Stack
```yaml
# monitoring-stack.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./alert_rules.yml:/etc/prometheus/alert_rules.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources

  postgres-exporter:
    image: prometheuscommunity/postgres-exporter:latest
    container_name: postgres-exporter
    ports:
      - "9187:9187"
    environment:
      - DATA_SOURCE_NAME=postgresql://postgres:password@postgres:5432/authdb?sslmode=disable

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: redis-exporter
    ports:
      - "9121:9121"
    environment:
      - REDIS_ADDR=redis:6379

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

volumes:
  prometheus_data:
  alertmanager_data:
  grafana_data:
```

## Alerting Rules

### alert_rules.yml
```yaml
groups:
  - name: auth-system-alerts
    rules:
      # High error rate
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }} for {{ $labels.job }}"

      # High response time
      - alert: HighResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High response time detected"
          description: "95th percentile response time is {{ $value }}s for {{ $labels.job }}"

      # Service down
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
          description: "{{ $labels.job }} has been down for more than 1 minute"

      # Database connection issues
      - alert: DatabaseConnectionsHigh
        expr: pg_stat_database_numbackends > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High number of database connections"
          description: "Database has {{ $value }} active connections"

      # Memory usage
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage"
          description: "Memory usage is {{ $value | humanizePercentage }}"

      # Disk space
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space"
          description: "Disk space is {{ $value | humanizePercentage }} full"

      # Authentication failures
      - alert: HighAuthFailureRate
        expr: rate(auth_attempts_total{result="failure"}[5m]) / rate(auth_attempts_total[5m]) > 0.2
        for: 3m
        labels:
          severity: warning
        annotations:
          summary: "High authentication failure rate"
          description: "Authentication failure rate is {{ $value | humanizePercentage }}"

      # Redis down
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Redis is down"
          description: "Redis instance has been down for more than 1 minute"

      # Certificate expiration
      - alert: CertificateExpiringSoon
        expr: (ssl_certificate_expiry_seconds - time()) / 86400 < 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon"
          description: "Certificate expires in {{ $value }} days"
```

## Dashboard Configuration

### Grafana Datasource Configuration
```yaml
# grafana/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

### Main Dashboard JSON
```json
{
  "dashboard": {
    "id": null,
    "title": "Auth System Overview",
    "tags": ["auth", "system"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{status}}"
          }
        ],
        "yAxes": [
          {
            "label": "Requests/sec",
            "min": 0
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "50th percentile"
          },
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "99th percentile"
          }
        ],
        "yAxes": [
          {
            "label": "Seconds",
            "min": 0
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Authentication Success Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(auth_attempts_total{result=\"success\"}[5m]) / rate(auth_attempts_total[5m]) * 100",
            "legendFormat": "Success Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "thresholds": {
              "steps": [
                {"color": "red", "value": 0},
                {"color": "yellow", "value": 80},
                {"color": "green", "value": 95}
              ]
            }
          }
        },
        "gridPos": {
          "h": 8,
          "w": 6,
          "x": 0,
          "y": 8
        }
      },
      {
        "id": 4,
        "title": "Active Sessions",
        "type": "stat",
        "targets": [
          {
            "expr": "active_sessions_total",
            "legendFormat": "Active Sessions"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 6,
          "x": 6,
          "y": 8
        }
      },
      {
        "id": 5,
        "title": "Database Connections",
        "type": "graph",
        "targets": [
          {
            "expr": "pg_stat_database_numbackends",
            "legendFormat": "Active Connections"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 8
        }
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
```

## Log Management

### Centralized Logging with ELK Stack

#### docker-compose-logging.yml
```yaml
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - xpack.security.enabled=false
    ports:
      - "9200:9200"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    container_name: logstash
    ports:
      - "5044:5044"
    volumes:
      - ./logstash.conf:/usr/share/logstash/pipeline/logstash.conf
    depends_on:
      - elasticsearch

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch

volumes:
  elasticsearch_data:
```

#### Logstash Configuration
```ruby
# logstash.conf
input {
  beats {
    port => 5044
  }
}

filter {
  if [fields][service] == "auth-grpc" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:timestamp} \[%{LOGLEVEL:level}\] %{GREEDYDATA:message}" }
    }
    
    date {
      match => [ "timestamp", "ISO8601" ]
    }
    
    if [level] == "ERROR" {
      mutate {
        add_tag => [ "error" ]
      }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "auth-system-%{+YYYY.MM.dd}"
  }
  
  stdout {
    codec => rubydebug
  }
}
```

### Application Logging Configuration

#### .NET Structured Logging
```csharp
// Program.cs
using Serilog;
using Serilog.Events;

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
    .MinimumLevel.Override("System", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .Enrich.WithProperty("Service", "AuthGrpc")
    .Enrich.WithProperty("Version", "1.0.0")
    .WriteTo.Console(outputTemplate: 
        "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}")
    .WriteTo.File("logs/auth-service-.log", 
        rollingInterval: RollingInterval.Day,
        retainedFileCountLimit: 7,
        outputTemplate: 
        "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}")
    .WriteTo.Elasticsearch(new ElasticsearchSinkOptions(new Uri("http://elasticsearch:9200"))
    {
        IndexFormat = "auth-system-{0:yyyy.MM.dd}",
        AutoRegisterTemplate = true,
        AutoRegisterTemplateVersion = AutoRegisterTemplateVersion.ESv7
    })
    .CreateLogger();

builder.Host.UseSerilog();
```

## Health Checks

### Application Health Checks

#### .NET Health Check Configuration
```csharp
// Program.cs
builder.Services.AddHealthChecks()
    .AddNpgSql(connectionString, name: "database")
    .AddRedis(redisConnectionString, name: "redis")
    .AddUrlGroup(new Uri("http://external-service/health"), name: "external-service")
    .AddCheck<CustomHealthCheck>("custom-check");

// Custom health check
public class CustomHealthCheck : IHealthCheck
{
    private readonly IServiceProvider _serviceProvider;

    public CustomHealthCheck(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Perform custom health checks
            using var scope = _serviceProvider.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<AuthDbContext>();
            
            // Check database connectivity
            await dbContext.Database.CanConnectAsync(cancellationToken);
            
            // Check critical business logic
            var userCount = await dbContext.Users.CountAsync(cancellationToken);
            
            var data = new Dictionary<string, object>
            {
                ["user_count"] = userCount,
                ["timestamp"] = DateTime.UtcNow
            };

            return HealthCheckResult.Healthy("All systems operational", data);
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy("Health check failed", ex);
        }
    }
}

// Configure health check endpoint
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
});
```

### Infrastructure Health Monitoring

#### Docker Health Checks
```dockerfile
# Dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:9.0

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["dotnet", "Auth.Grpc.dll"]
```

#### Kubernetes Health Checks
```yaml
# k8s-deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-grpc-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: auth-grpc-service
  template:
    metadata:
      labels:
        app: auth-grpc-service
    spec:
      containers:
      - name: auth-grpc
        image: auth-grpc:latest
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

## Deployment and Maintenance

### Monitoring Stack Deployment
```bash
#!/bin/bash
# deploy-monitoring.sh

echo "Deploying monitoring stack..."

# Create monitoring network
docker network create monitoring

# Deploy Prometheus
docker run -d \
  --name prometheus \
  --network monitoring \
  -p 9090:9090 \
  -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml \
  -v $(pwd)/alert_rules.yml:/etc/prometheus/alert_rules.yml \
  prom/prometheus:latest

# Deploy AlertManager
docker run -d \
  --name alertmanager \
  --network monitoring \
  -p 9093:9093 \
  -v $(pwd)/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager:latest

# Deploy Grafana
docker run -d \
  --name grafana \
  --network monitoring \
  -p 3001:3000 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -v grafana_data:/var/lib/grafana \
  grafana/grafana:latest

echo "Monitoring stack deployed successfully!"
echo "Prometheus: http://localhost:9090"
echo "AlertManager: http://localhost:9093"
echo "Grafana: http://localhost:3001 (admin/admin)"
```

### Monitoring Maintenance
```bash
#!/bin/bash
# monitoring-maintenance.sh

echo "=== Monitoring Maintenance $(date) ==="

# Check monitoring services
docker ps --filter "name=prometheus" --filter "name=grafana" --filter "name=alertmanager"

# Clean up old metrics data
docker exec prometheus prometheus_tsdb_tool delete-series --match='{__name__=~".*"}' --min-time=$(date -d '30 days ago' +%s)000

# Backup Grafana dashboards
docker exec grafana grafana-cli admin export-dashboard > grafana-backup-$(date +%Y%m%d).json

# Check disk usage
df -h /var/lib/docker/volumes/prometheus_data
df -h /var/lib/docker/volumes/grafana_data

echo "Monitoring maintenance completed"
```

This monitoring and alerting setup provides comprehensive visibility into your authentication system's health and performance, enabling proactive issue detection and resolution.