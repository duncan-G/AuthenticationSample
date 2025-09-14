# Database Setup with PostgreSQL and Redis

## Overview

The authentication system uses a dual-database architecture with PostgreSQL as the primary relational database for user data and application state, and Redis for caching, session storage, and rate limiting. This combination provides both ACID compliance for critical data and high-performance caching for frequently accessed information.

## Implementation

### PostgreSQL Database

#### Architecture
- **Primary Database**: PostgreSQL 15+ with pg_cron extension
- **Connection Pooling**: Built-in .NET connection pooling
- **Migrations**: Entity Framework Core migrations
- **Backup Strategy**: Automated backups with point-in-time recovery
- **High Availability**: Single-AZ deployment with automated failover

#### Database Schema

The system uses Entity Framework Core with a code-first approach:

```csharp
// User entity
public class User
{
    public Guid Id { get; set; }
    public string Email { get; set; }
    public string PasswordHash { get; set; }
    public bool EmailVerified { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    
    // Navigation properties
    public ICollection<UserSession> Sessions { get; set; }
    public ICollection<VerificationCode> VerificationCodes { get; set; }
}

// User session tracking
public class UserSession
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string SessionToken { get; set; }
    public DateTime ExpiresAt { get; set; }
    public string IpAddress { get; set; }
    public string UserAgent { get; set; }
    
    public User User { get; set; }
}
```

#### Connection Configuration

```csharp
// Program.cs - Database configuration
builder.Services.AddDbContext<AuthDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
    options.UseNpgsql(connectionString, npgsqlOptions =>
    {
        npgsqlOptions.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorCodesToAdd: null);
    });
    
    // Enable sensitive data logging in development
    if (builder.Environment.IsDevelopment())
    {
        options.EnableSensitiveDataLogging();
        options.EnableDetailedErrors();
    }
});
```

### Redis Cache

#### Architecture
- **Caching Layer**: Redis 7+ for high-performance caching
- **Session Storage**: Distributed session management
- **Rate Limiting**: Sliding window and fixed window algorithms
- **Pub/Sub**: Real-time notifications and events
- **Persistence**: RDB snapshots with AOF logging

#### Redis Configuration

```yaml
# redis.conf
# Memory management
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# AOF persistence
appendonly yes
appendfsync everysec

# Security
requirepass ${REDIS_PASSWORD}
```

#### Connection Setup

```csharp
// Redis configuration
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
    options.InstanceName = "AuthSample";
});

// Redis connection multiplexer
builder.Services.AddSingleton<IConnectionMultiplexer>(provider =>
{
    var configuration = provider.GetService<IConfiguration>();
    var connectionString = configuration.GetConnectionString("Redis");
    return ConnectionMultiplexer.Connect(connectionString);
});
```

### Docker Stack Configuration

#### PostgreSQL Stack

```yaml
# postgres.stack.debug.yaml
version: "3.8"
services:
  postgres:
    image: authentication-sample/postgres:latest
    environment:
      POSTGRES_DB: ${DATABASE_NAME}
      POSTGRES_USER: ${DATABASE_USER}
      POSTGRES_PASSWORD: ${DATABASE_PASSWORD}
    command: [
      "postgres",
      "-c", "shared_preload_libraries=pg_cron",
      "-c", "cron.database_name=${DATABASE_NAME}",
      "-c", "log_statement=all",
      "-c", "log_min_duration_statement=1000"
    ]
    ports:
      - "5432:5432"
    networks:
      - net
    volumes:
      - db_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    deploy:
      mode: global
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M

volumes:
  db_data:
    driver: local

networks:
  net:
    external: true
```

#### Redis Stack

```yaml
# redis.stack.debug.yaml
version: "3.8"
services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    ports:
      - "6379:6379"
    networks:
      - net
    volumes:
      - redis_data:/data
      - ./redis.conf:/usr/local/etc/redis/redis.conf:ro
    deploy:
      mode: global
      restart_policy:
        condition: on-failure
        delay: 15s
        max_attempts: 3
        window: 120s
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M

volumes:
  redis_data:
    driver: local

networks:
  net:
    external: true
```

### Database Migrations

#### Entity Framework Migrations

```csharp
// Initial migration
public partial class InitialCreate : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.CreateTable(
            name: "Users",
            columns: table => new
            {
                Id = table.Column<Guid>(type: "uuid", nullable: false),
                Email = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: false),
                PasswordHash = table.Column<string>(type: "text", nullable: true),
                EmailVerified = table.Column<bool>(type: "boolean", nullable: false),
                CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("PK_Users", x => x.Id);
            });

        migrationBuilder.CreateIndex(
            name: "IX_Users_Email",
            table: "Users",
            column: "Email",
            unique: true);
    }
}
```

#### Migration Commands

```bash
# Create new migration
dotnet ef migrations add MigrationName --project Auth.Infrastructure --startup-project Auth.Grpc

# Update database
dotnet ef database update --project Auth.Infrastructure --startup-project Auth.Grpc

# Generate SQL script
dotnet ef migrations script --project Auth.Infrastructure --startup-project Auth.Grpc
```

### DynamoDB Integration

#### Refresh Token Storage

For production scalability, refresh tokens are stored in DynamoDB:

```hcl
# DynamoDB table for refresh tokens
resource "aws_dynamodb_table" "refresh_tokens" {
  name         = "${var.project_name}_${var.env}_RefreshTokens"
  billing_mode = "PAY_PER_REQUEST"
  
  hash_key  = "pk"
  range_key = "sk"
  
  attribute {
    name = "pk"
    type = "S"
  }
  
  attribute {
    name = "sk"
    type = "S"
  }
  
  server_side_encryption {
    enabled = true
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = {
    Environment = var.env
    Purpose     = "Refresh tokens storage"
  }
}
```

#### DynamoDB Access Pattern

```csharp
// DynamoDB refresh token store
public class DynamoDbRefreshTokenStore : IRefreshTokenStore
{
    private readonly IAmazonDynamoDB _dynamoDb;
    private readonly string _tableName;
    
    public async Task StoreRefreshTokenAsync(RefreshToken token)
    {
        var item = new Dictionary<string, AttributeValue>
        {
            ["pk"] = new AttributeValue($"RTID#{token.Id}"),
            ["sk"] = new AttributeValue("v1"),
            ["userSub"] = new AttributeValue(token.UserSub),
            ["refreshToken"] = new AttributeValue(token.Token),
            ["issuedAtUtc"] = new AttributeValue(token.IssuedAt.ToString("O")),
            ["expiresAtUtc"] = new AttributeValue(token.ExpiresAt.ToString("O"))
        };
        
        await _dynamoDb.PutItemAsync(_tableName, item);
    }
}
```

## Configuration

### Connection Strings

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=postgres;Database=authsample;Username=postgres;Password=secure_password;Include Error Detail=true",
    "Redis": "redis:6379,password=redis_password,abortConnect=false"
  }
}
```

### Environment Variables

```bash
# PostgreSQL configuration
export DATABASE_NAME="authsample"
export DATABASE_USER="postgres"
export DATABASE_PASSWORD="secure_password"
export DATABASE_HOST="postgres"
export DATABASE_PORT="5432"

# Redis configuration
export REDIS_HOST="redis"
export REDIS_PORT="6379"
export REDIS_PASSWORD="redis_password"

# DynamoDB configuration (production)
export DYNAMODB_REFRESH_TOKENS_TABLE="auth-sample_prod_RefreshTokens"
export AWS_REGION="us-east-1"
```

### Database Initialization

```sql
-- init.sql - Database initialization script
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Create application user
CREATE USER authapp WITH PASSWORD 'app_password';
GRANT CONNECT ON DATABASE authsample TO authapp;
GRANT USAGE ON SCHEMA public TO authapp;
GRANT CREATE ON SCHEMA public TO authapp;

-- Set up connection limits
ALTER USER authapp CONNECTION LIMIT 20;
```

## Usage

### Development Environment

#### Starting Database Services

1. **Start PostgreSQL**:
   ```bash
   docker stack deploy -c infrastructure/postgres/postgres.stack.debug.yaml postgres
   ```

2. **Start Redis**:
   ```bash
   docker stack deploy -c infrastructure/redis/redis.stack.debug.yaml redis
   ```

3. **Verify Connectivity**:
   ```bash
   # Test PostgreSQL connection
   docker exec -it $(docker ps -q -f name=postgres) psql -U postgres -d authsample -c "SELECT version();"
   
   # Test Redis connection
   docker exec -it $(docker ps -q -f name=redis) redis-cli -a redis_password ping
   ```

#### Database Operations

```bash
# Run migrations
dotnet ef database update --project microservices/Auth/src/Auth.Infrastructure --startup-project microservices/Auth/src/Auth.Grpc

# Seed test data
dotnet run --project microservices/Auth/src/Auth.Grpc -- --seed-data

# Backup database
docker exec $(docker ps -q -f name=postgres) pg_dump -U postgres authsample > backup.sql
```

### Production Operations

#### Database Monitoring

```bash
# PostgreSQL performance monitoring
docker exec -it postgres psql -U postgres -d authsample -c "
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes
FROM pg_stat_user_tables;
"

# Redis monitoring
docker exec -it redis redis-cli -a redis_password info stats
```

#### Backup and Recovery

```bash
# PostgreSQL backup
docker exec postgres pg_dump -U postgres -Fc authsample > authsample_backup.dump

# PostgreSQL restore
docker exec -i postgres pg_restore -U postgres -d authsample < authsample_backup.dump

# Redis backup
docker exec redis redis-cli -a redis_password BGSAVE
```

## Testing

### Database Testing

1. **Connection Testing**:
   ```bash
   # Test PostgreSQL connection
   dotnet test --filter "Category=Database" --logger "console;verbosity=detailed"
   
   # Test Redis connection
   dotnet test --filter "Category=Cache" --logger "console;verbosity=detailed"
   ```

2. **Migration Testing**:
   ```bash
   # Test migrations on clean database
   docker exec postgres dropdb -U postgres authsample_test
   docker exec postgres createdb -U postgres authsample_test
   dotnet ef database update --connection "Host=postgres;Database=authsample_test;Username=postgres;Password=secure_password"
   ```

3. **Performance Testing**:
   ```bash
   # PostgreSQL performance test
   docker exec postgres pgbench -U postgres -i -s 10 authsample
   docker exec postgres pgbench -U postgres -c 10 -j 2 -t 1000 authsample
   
   # Redis performance test
   docker exec redis redis-cli -a redis_password --latency-history -i 1
   ```

### Integration Testing

```csharp
// Database integration test
[Test]
public async Task UserRepository_CreateUser_ShouldPersistToDatabase()
{
    // Arrange
    using var context = new AuthDbContext(_dbContextOptions);
    var repository = new UserRepository(context);
    var user = new User
    {
        Email = "test@example.com",
        PasswordHash = "hashed_password",
        EmailVerified = false
    };
    
    // Act
    await repository.CreateAsync(user);
    await context.SaveChangesAsync();
    
    // Assert
    var savedUser = await repository.GetByEmailAsync("test@example.com");
    Assert.That(savedUser, Is.Not.Null);
    Assert.That(savedUser.Email, Is.EqualTo("test@example.com"));
}
```

## Troubleshooting

### Common Issues

#### 1. Connection Pool Exhaustion

```bash
# Check active connections
docker exec postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';"

# Monitor connection pool
docker logs auth-service | grep -i "connection pool"
```

#### 2. Redis Memory Issues

```bash
# Check Redis memory usage
docker exec redis redis-cli -a redis_password info memory

# Monitor Redis performance
docker exec redis redis-cli -a redis_password --stat
```

#### 3. Migration Failures

```bash
# Check migration history
dotnet ef migrations list --project Auth.Infrastructure --startup-project Auth.Grpc

# Rollback migration
dotnet ef database update PreviousMigrationName --project Auth.Infrastructure --startup-project Auth.Grpc
```

#### 4. DynamoDB Access Issues

```bash
# Test DynamoDB connectivity
aws dynamodb describe-table --table-name auth-sample_prod_RefreshTokens

# Check IAM permissions
aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::123456789012:role/auth-sample-ec2-worker-role-prod --action-names dynamodb:PutItem --resource-arns arn:aws:dynamodb:us-east-1:123456789012:table/auth-sample_prod_RefreshTokens
```

### Performance Optimization

#### PostgreSQL Tuning

```sql
-- Optimize PostgreSQL settings
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;

-- Reload configuration
SELECT pg_reload_conf();
```

#### Redis Optimization

```bash
# Redis performance tuning
redis-cli -a redis_password CONFIG SET maxmemory-policy allkeys-lru
redis-cli -a redis_password CONFIG SET tcp-keepalive 60
redis-cli -a redis_password CONFIG SET timeout 300
```

### Monitoring Queries

```sql
-- PostgreSQL slow queries
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;

-- Active connections
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    query
FROM pg_stat_activity 
WHERE state = 'active';
```

## Related Features

- [User Authentication](../authentication/user-signin.md) - Database-backed user authentication
- [Session Management](../authentication/session-management.md) - Redis-based session storage
- [Rate Limiting](../security/rate-limiting.md) - Redis-based rate limiting algorithms
- [Monitoring and Observability](monitoring-observability.md) - Database performance monitoring