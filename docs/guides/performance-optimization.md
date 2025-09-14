# Performance Optimization Guide

This guide provides detailed strategies for optimizing the performance of the authentication system across all components.

## Table of Contents

- [Performance Monitoring](#performance-monitoring)
- [Application Performance](#application-performance)
- [Database Performance](#database-performance)
- [Frontend Performance](#frontend-performance)
- [Infrastructure Performance](#infrastructure-performance)
- [Caching Strategies](#caching-strategies)
- [Load Testing](#load-testing)

## Performance Monitoring

### Key Performance Indicators (KPIs)

#### Application Metrics
```csharp
// Custom metrics in .NET services
public class PerformanceMetrics
{
    private static readonly Counter AuthenticationAttempts = Metrics
        .CreateCounter("auth_attempts_total", "Total authentication attempts");
    
    private static readonly Histogram RequestDuration = Metrics
        .CreateHistogram("request_duration_seconds", "Request duration in seconds");
    
    private static readonly Gauge ActiveSessions = Metrics
        .CreateGauge("active_sessions", "Number of active user sessions");

    public static void RecordAuthAttempt(bool success)
    {
        AuthenticationAttempts.WithLabels(success ? "success" : "failure").Inc();
    }

    public static void RecordRequestDuration(double duration)
    {
        RequestDuration.Observe(duration);
    }
}
```

#### Database Metrics
```sql
-- Monitor query performance
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    stddev_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
ORDER BY total_time DESC 
LIMIT 20;

-- Monitor connection usage
SELECT 
    state,
    count(*) as connections
FROM pg_stat_activity 
GROUP BY state;

-- Monitor lock waits
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

### Monitoring Setup

#### Prometheus Configuration
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'auth-services'
    static_configs:
      - targets: ['auth-grpc-service:8080']
    metrics_path: /metrics
    scrape_interval: 10s
    
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
    
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
```

### Grafana Dashboards
```json
{
  "dashboard": {
    "title": "Auth System Performance",
    "panels": [
      {
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{status}}"
          }
        ]
      },
      {
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ]
  }
}
```

## Application Performance

### .NET Service Optimization

#### Startup Configuration
```csharp
// Program.cs - Optimized configuration
var builder = WebApplication.CreateBuilder(args);

// Configure Kestrel for performance
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxConcurrentConnections = 1000;
    options.Limits.MaxConcurrentUpgradedConnections = 1000;
    options.Limits.MaxRequestBodySize = 10 * 1024 * 1024; // 10MB
    options.Limits.MinRequestBodyDataRate = new MinDataRate(100, TimeSpan.FromSeconds(10));
    options.Limits.MinResponseDataRate = new MinDataRate(100, TimeSpan.FromSeconds(10));
});

// Configure gRPC for performance
builder.Services.AddGrpc(options =>
{
    options.MaxReceiveMessageSize = 4 * 1024 * 1024; // 4MB
    options.MaxSendMessageSize = 4 * 1024 * 1024; // 4MB
    options.EnableDetailedErrors = false; // Disable in production
});

// Configure compression
builder.Services.AddGrpcReflection();
builder.Services.Configure<GzipCompressionProviderOptions>(options =>
{
    options.Level = CompressionLevel.Fastest;
});

// Configure JSON serialization
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
});
```

#### Memory Management
```csharp
// Optimize object pooling
public class ObjectPoolService
{
    private readonly ObjectPool<StringBuilder> _stringBuilderPool;
    private readonly ObjectPool<List<string>> _listPool;

    public ObjectPoolService(ObjectPoolProvider poolProvider)
    {
        _stringBuilderPool = poolProvider.CreateStringBuilderPool();
        _listPool = poolProvider.Create<List<string>>();
    }

    public string ProcessData(IEnumerable<string> data)
    {
        var sb = _stringBuilderPool.Get();
        var list = _listPool.Get();
        
        try
        {
            list.AddRange(data);
            foreach (var item in list)
            {
                sb.AppendLine(item);
            }
            return sb.ToString();
        }
        finally
        {
            _stringBuilderPool.Return(sb);
            list.Clear();
            _listPool.Return(list);
        }
    }
}

// Configure object pools
builder.Services.AddSingleton<ObjectPoolProvider, DefaultObjectPoolProvider>();
builder.Services.AddSingleton<ObjectPoolService>();
```

#### Async Optimization
```csharp
// Optimized async patterns
public class OptimizedAuthService
{
    private readonly HttpClient _httpClient;
    private readonly SemaphoreSlim _semaphore;

    public OptimizedAuthService(HttpClient httpClient)
    {
        _httpClient = httpClient;
        _semaphore = new SemaphoreSlim(10, 10); // Limit concurrent operations
    }

    public async Task<AuthResult> AuthenticateAsync(string token)
    {
        await _semaphore.WaitAsync();
        try
        {
            // Use ConfigureAwait(false) for library code
            var response = await _httpClient.GetAsync($"/validate/{token}")
                .ConfigureAwait(false);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync()
                    .ConfigureAwait(false);
                return JsonSerializer.Deserialize<AuthResult>(content);
            }
            
            return AuthResult.Failed();
        }
        finally
        {
            _semaphore.Release();
        }
    }

    // Batch operations for better performance
    public async Task<IEnumerable<AuthResult>> AuthenticateBatchAsync(IEnumerable<string> tokens)
    {
        var tasks = tokens.Select(token => AuthenticateAsync(token));
        return await Task.WhenAll(tasks);
    }
}
```

### gRPC Performance

#### Service Implementation
```csharp
// Optimized gRPC service
public class OptimizedSignUpService : SignUpServiceBase
{
    private readonly IMemoryCache _cache;
    private readonly ILogger<OptimizedSignUpService> _logger;

    public override async Task<SignUpResponse> SignUp(SignUpRequest request, ServerCallContext context)
    {
        using var activity = Activity.StartActivity("SignUp");
        activity?.SetTag("user.email", request.Email);

        // Input validation with early return
        if (string.IsNullOrEmpty(request.Email))
        {
            throw new RpcException(new Status(StatusCode.InvalidArgument, "Email is required"));
        }

        // Check cache first
        var cacheKey = $"signup_attempt:{request.Email}";
        if (_cache.TryGetValue(cacheKey, out _))
        {
            throw new RpcException(new Status(StatusCode.ResourceExhausted, "Too many attempts"));
        }

        try
        {
            // Process signup
            var result = await ProcessSignUpAsync(request);
            
            // Cache the attempt
            _cache.Set(cacheKey, true, TimeSpan.FromMinutes(5));
            
            return result;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SignUp failed for {Email}", request.Email);
            throw new RpcException(new Status(StatusCode.Internal, "SignUp failed"));
        }
    }

    // Streaming for bulk operations
    public override async Task SignUpBatch(
        IAsyncStreamReader<SignUpRequest> requestStream,
        IServerStreamWriter<SignUpResponse> responseStream,
        ServerCallContext context)
    {
        await foreach (var request in requestStream.ReadAllAsync())
        {
            try
            {
                var response = await ProcessSignUpAsync(request);
                await responseStream.WriteAsync(response);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Batch signup failed for {Email}", request.Email);
                // Continue processing other requests
            }
        }
    }
}
```

## Database Performance

### Query Optimization

#### Index Strategy
```sql
-- Create optimal indexes
CREATE INDEX CONCURRENTLY idx_users_email_hash ON users USING hash(email);
CREATE INDEX CONCURRENTLY idx_users_created_at_desc ON users(created_at DESC);
CREATE INDEX CONCURRENTLY idx_sessions_user_expires ON user_sessions(user_id, expires_at);

-- Partial indexes for common conditions
CREATE INDEX CONCURRENTLY idx_users_active ON users(id) WHERE is_active = true;
CREATE INDEX CONCURRENTLY idx_sessions_active ON user_sessions(user_id) WHERE expires_at > NOW();

-- Composite indexes for complex queries
CREATE INDEX CONCURRENTLY idx_users_email_status ON users(email, status) WHERE status IN ('active', 'pending');
```

#### Query Patterns
```sql
-- Optimized user lookup
PREPARE get_user_by_email (text) AS
SELECT id, email, status, created_at 
FROM users 
WHERE email = $1 AND is_active = true;

-- Batch user operations
PREPARE get_users_batch (text[]) AS
SELECT id, email, status 
FROM users 
WHERE email = ANY($1) AND is_active = true;

-- Efficient session cleanup
PREPARE cleanup_expired_sessions AS
DELETE FROM user_sessions 
WHERE expires_at < NOW() - INTERVAL '1 hour'
RETURNING user_id;
```

### Connection Pool Optimization

#### Entity Framework Configuration
```csharp
// Optimized DbContext configuration
public class OptimizedAuthDbContext : DbContext
{
    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        optionsBuilder.UseNpgsql(connectionString, options =>
        {
            options.EnableRetryOnFailure(3, TimeSpan.FromSeconds(5), null);
            options.CommandTimeout(30);
            options.EnableServiceProviderCaching();
            options.EnableSensitiveDataLogging(false);
        });

        // Configure query behavior
        optionsBuilder.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
        optionsBuilder.EnableSensitiveDataLogging(false);
        optionsBuilder.EnableDetailedErrors(false);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Configure entity tracking
        modelBuilder.Entity<User>()
            .HasQueryFilter(u => u.IsActive);

        // Configure value converters for performance
        modelBuilder.Entity<User>()
            .Property(u => u.CreatedAt)
            .HasConversion(
                v => v.ToUniversalTime(),
                v => DateTime.SpecifyKind(v, DateTimeKind.Utc));
    }
}

// Connection pool configuration
services.AddDbContextPool<AuthDbContext>(options =>
    options.UseNpgsql(connectionString), poolSize: 128);
```

#### Connection Management
```csharp
// Custom connection factory
public class OptimizedConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;
    private readonly SemaphoreSlim _semaphore;

    public OptimizedConnectionFactory(string connectionString)
    {
        _connectionString = connectionString;
        _semaphore = new SemaphoreSlim(50, 50); // Limit concurrent connections
    }

    public async Task<IDbConnection> CreateConnectionAsync()
    {
        await _semaphore.WaitAsync();
        try
        {
            var connection = new NpgsqlConnection(_connectionString);
            await connection.OpenAsync();
            return connection;
        }
        catch
        {
            _semaphore.Release();
            throw;
        }
    }

    public void ReleaseConnection(IDbConnection connection)
    {
        connection?.Dispose();
        _semaphore.Release();
    }
}
```

### Database Maintenance

#### Automated Optimization
```sql
-- Automated maintenance procedure
CREATE OR REPLACE FUNCTION optimize_database()
RETURNS void AS $$
DECLARE
    table_name text;
BEGIN
    -- Update statistics
    FOR table_name IN 
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ANALYZE ' || quote_ident(table_name);
    END LOOP;

    -- Vacuum tables
    VACUUM (ANALYZE, VERBOSE);

    -- Reindex if needed
    REINDEX DATABASE authdb;
    
    RAISE NOTICE 'Database optimization completed';
END;
$$ LANGUAGE plpgsql;

-- Schedule optimization
SELECT cron.schedule('optimize-db', '0 2 * * *', 'SELECT optimize_database();');
```

## Frontend Performance

### Next.js Optimization

#### Build Configuration
```javascript
// next.config.ts
const nextConfig = {
  // Enable SWC minification
  swcMinify: true,
  
  // Optimize images
  images: {
    formats: ['image/webp', 'image/avif'],
    deviceSizes: [640, 750, 828, 1080, 1200, 1920, 2048, 3840],
    imageSizes: [16, 32, 48, 64, 96, 128, 256, 384],
    minimumCacheTTL: 60,
  },
  
  // Enable experimental features
  experimental: {
    optimizeCss: true,
    optimizePackageImports: [
      '@radix-ui/react-icons',
      'lucide-react',
    ],
    turbo: {
      rules: {
        '*.svg': {
          loaders: ['@svgr/webpack'],
          as: '*.js',
        },
      },
    },
  },
  
  // Webpack optimizations
  webpack: (config, { dev, isServer }) => {
    if (!dev && !isServer) {
      config.optimization.splitChunks = {
        chunks: 'all',
        cacheGroups: {
          vendor: {
            test: /[\\/]node_modules[\\/]/,
            name: 'vendors',
            chunks: 'all',
          },
          common: {
            name: 'common',
            minChunks: 2,
            chunks: 'all',
            enforce: true,
          },
        },
      };
    }
    return config;
  },
  
  // Headers for caching
  async headers() {
    return [
      {
        source: '/_next/static/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=31536000, immutable',
          },
        ],
      },
      {
        source: '/api/:path*',
        headers: [
          {
            key: 'Cache-Control',
            value: 'public, max-age=300, stale-while-revalidate=60',
          },
        ],
      },
    ];
  },
};
```

#### Component Optimization
```typescript
// Optimized React components
import { memo, useMemo, useCallback } from 'react';
import { debounce } from 'lodash-es';

// Memoized component
export const OptimizedAuthForm = memo(({ onSubmit, initialValues }) => {
  // Memoize expensive calculations
  const validationRules = useMemo(() => ({
    email: { required: true, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ },
    password: { required: true, minLength: 8 },
  }), []);

  // Debounced validation
  const debouncedValidate = useCallback(
    debounce((values) => {
      // Validation logic
    }, 300),
    []
  );

  // Memoized submit handler
  const handleSubmit = useCallback((values) => {
    onSubmit(values);
  }, [onSubmit]);

  return (
    <form onSubmit={handleSubmit}>
      {/* Form fields */}
    </form>
  );
});

// Virtual scrolling for large lists
import { FixedSizeList as List } from 'react-window';

export const OptimizedUserList = ({ users }) => {
  const Row = useCallback(({ index, style }) => (
    <div style={style}>
      <UserItem user={users[index]} />
    </div>
  ), [users]);

  return (
    <List
      height={600}
      itemCount={users.length}
      itemSize={50}
      width="100%"
    >
      {Row}
    </List>
  );
};
```

#### Bundle Optimization
```typescript
// Code splitting and lazy loading
import { lazy, Suspense } from 'react';
import dynamic from 'next/dynamic';

// Lazy load heavy components
const HeavyComponent = lazy(() => import('./HeavyComponent'));

// Dynamic imports with loading states
const DynamicComponent = dynamic(
  () => import('./DynamicComponent'),
  {
    loading: () => <div>Loading...</div>,
    ssr: false, // Disable SSR for client-only components
  }
);

// Tree shaking optimization
import { debounce } from 'lodash-es/debounce'; // Import specific functions
import { Button } from '@radix-ui/react-button'; // Import specific components
```

## Infrastructure Performance

### Container Optimization

#### Docker Configuration
```dockerfile
# Multi-stage build for smaller images
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy and restore dependencies first (better caching)
COPY ["*.csproj", "./"]
RUN dotnet restore

# Copy source and build
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Optimize runtime
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
ENV DOTNET_RUNNING_IN_CONTAINER=true
ENV ASPNETCORE_URLS=http://+:8080

# Copy published app
COPY --from=build /app/publish .

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["dotnet", "Auth.Grpc.dll"]
```

#### Docker Compose Optimization
```yaml
# docker-compose.yml
version: '3.8'

services:
  auth-grpc-service:
    image: auth-grpc:latest
    deploy:
      replicas: 3
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    environment:
      - ASPNETCORE_ENVIRONMENT=Production
      - DOTNET_GCServer=1
      - DOTNET_GCConcurrent=1
    networks:
      - auth-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  auth-network:
    driver: overlay
    attachable: true
```

### Load Balancer Optimization

#### Envoy Configuration
```yaml
# envoy.yaml - Performance optimized
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          access_log:
          - name: envoy.access_loggers.stdout
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.access_loggers.stream.v3.StdoutAccessLog
          http_filters:
          - name: envoy.filters.http.compression
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.compression.v3.Compressor
              response_direction_config:
                common_config:
                  min_content_length: 100
                  content_type:
                  - "application/grpc-web+proto"
                  - "application/grpc-web-text+proto"
              compressor_library:
                name: gzip
                typed_config:
                  "@type": type.googleapis.com/envoy.extensions.compression.gzip.compressor.v3.Gzip
                  memory_level: 3
                  window_bits: 12
          - name: envoy.filters.http.grpc_web
          - name: envoy.filters.http.cors
          - name: envoy.filters.http.router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: auth_service
                  timeout: 30s

  clusters:
  - name: auth_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    http2_protocol_options: {}
    health_checks:
    - timeout: 1s
      interval: 10s
      unhealthy_threshold: 3
      healthy_threshold: 2
      http_health_check:
        path: "/health"
    load_assignment:
      cluster_name: auth_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: auth-grpc-service
                port_value: 8080
```

## Caching Strategies

### Multi-Level Caching

#### Application Cache
```csharp
// Distributed caching with Redis
public class CacheService
{
    private readonly IDistributedCache _distributedCache;
    private readonly IMemoryCache _memoryCache;
    private readonly ILogger<CacheService> _logger;

    public async Task<T> GetOrSetAsync<T>(
        string key,
        Func<Task<T>> getItem,
        TimeSpan? expiry = null)
    {
        // L1 Cache - Memory
        if (_memoryCache.TryGetValue(key, out T cachedItem))
        {
            return cachedItem;
        }

        // L2 Cache - Redis
        var distributedItem = await _distributedCache.GetStringAsync(key);
        if (distributedItem != null)
        {
            var item = JsonSerializer.Deserialize<T>(distributedItem);
            _memoryCache.Set(key, item, TimeSpan.FromMinutes(5));
            return item;
        }

        // Source
        var newItem = await getItem();
        if (newItem != null)
        {
            var serialized = JsonSerializer.Serialize(newItem);
            await _distributedCache.SetStringAsync(key, serialized, new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = expiry ?? TimeSpan.FromMinutes(30)
            });
            _memoryCache.Set(key, newItem, TimeSpan.FromMinutes(5));
        }

        return newItem;
    }
}
```

#### Redis Optimization
```bash
# Redis configuration for performance
redis-cli CONFIG SET maxmemory 1gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
redis-cli CONFIG SET save "900 1 300 10 60 10000"
redis-cli CONFIG SET tcp-keepalive 60
redis-cli CONFIG SET timeout 300

# Enable Redis clustering for scale
redis-cli --cluster create \
  127.0.0.1:7000 127.0.0.1:7001 127.0.0.1:7002 \
  127.0.0.1:7003 127.0.0.1:7004 127.0.0.1:7005 \
  --cluster-replicas 1
```

## Load Testing

### Performance Testing Setup

#### Artillery Configuration
```yaml
# load-test.yml
config:
  target: 'https://your-auth-system.com'
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm up"
    - duration: 300
      arrivalRate: 50
      name: "Sustained load"
    - duration: 120
      arrivalRate: 100
      name: "Peak load"
  processor: "./test-functions.js"

scenarios:
  - name: "Authentication flow"
    weight: 70
    flow:
      - post:
          url: "/api/auth/signup"
          json:
            email: "{{ $randomEmail() }}"
            password: "TestPassword123!"
      - think: 2
      - post:
          url: "/api/auth/signin"
          json:
            email: "{{ email }}"
            password: "TestPassword123!"

  - name: "Token validation"
    weight: 30
    flow:
      - get:
          url: "/api/auth/validate"
          headers:
            Authorization: "Bearer {{ $randomToken() }}"
```

#### K6 Load Testing
```javascript
// load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

export let errorRate = new Rate('errors');

export let options = {
  stages: [
    { duration: '2m', target: 100 }, // Ramp up
    { duration: '5m', target: 100 }, // Stay at 100 users
    { duration: '2m', target: 200 }, // Ramp up to 200 users
    { duration: '5m', target: 200 }, // Stay at 200 users
    { duration: '2m', target: 0 },   // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests under 500ms
    http_req_failed: ['rate<0.1'],    // Error rate under 10%
  },
};

export default function () {
  // Test authentication
  let response = http.post('https://your-auth-system.com/api/auth/signin', {
    email: 'test@example.com',
    password: 'password123',
  });

  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(response.status !== 200);
  sleep(1);
}
```

### Performance Benchmarks

#### Target Performance Metrics
```yaml
# performance-targets.yml
authentication:
  signup:
    p95_response_time: 500ms
    p99_response_time: 1000ms
    throughput: 1000 rps
    error_rate: <1%
  
  signin:
    p95_response_time: 200ms
    p99_response_time: 500ms
    throughput: 2000 rps
    error_rate: <0.5%

database:
  connection_pool_utilization: <80%
  query_response_time: <100ms
  lock_wait_time: <10ms

infrastructure:
  cpu_utilization: <70%
  memory_utilization: <80%
  disk_io_wait: <5%
```

Remember to continuously monitor and optimize performance based on real-world usage patterns and load testing results.