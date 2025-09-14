# Rate Limiting

## Overview

The authentication system implements a comprehensive rate limiting system using Redis-based algorithms to protect against abuse and ensure fair resource usage. The system supports both sliding window and fixed window rate limiting algorithms, with flexible configuration for different endpoints and user identifiers.

## Implementation

### Architecture

The rate limiting system implements a multi-layered approach with both API gateway and application-level rate limiting:

**API Gateway Layer (Envoy):**
- **Local Rate Limiting**: Envoy's built-in local rate limiter for immediate protection
- **Token Bucket Algorithm**: Fast, memory-efficient rate limiting at the proxy level
- **Per-Route Configuration**: Different rate limits for different endpoints

**Application Layer (.NET):**
- **RedisScriptRateLimiter**: Core rate limiter implementation using Lua scripts
- **Scripts**: Contains Lua scripts for sliding and fixed window algorithms
- **RateLimiterHttpContextExtensions**: Convenience methods for applying rate limits
- **Redis Integration**: Uses StackExchange.Redis for distributed rate limiting

### Multi-Layer Rate Limiting Flow

```text
┌─────────────────────────────────────────────────────────────┐
│                    Client Request                           │
├─────────────────────────────────────────────────────────────┤
│              Envoy Local Rate Limiter                       │
│              (Token Bucket - 50 req/sec)                    │
├─────────────────────────────────────────────────────────────┤
│                 gRPC Service                                │
├─────────────────────────────────────────────────────────────┤
│            Application Rate Limiter                         │
│         (Redis-based - Granular limits)                     │
├─────────────────────────────────────────────────────────────┤
│                Business Logic                               │
└─────────────────────────────────────────────────────────────┘
```

### Envoy Rate Limiting

#### Token Bucket Algorithm (Envoy Local Rate Limiter)

Envoy implements a token bucket algorithm for fast, local rate limiting at the API gateway level:

**Configuration Example:**
```yaml
typed_per_filter_config:
  envoy.filters.http.local_ratelimit:
    "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
    stat_prefix: http_local_rate_limiter
    token_bucket:
      max_tokens: 50        # Maximum tokens in bucket
      tokens_per_fill: 50   # Tokens added per fill interval
      fill_interval: 1s     # How often to add tokens
    filter_enabled:
      default_value:
        numerator: 100      # 100% of requests are evaluated
        denominator: HUNDRED
    filter_enforced:
      default_value:
        numerator: 100      # 100% of rate limit decisions are enforced
        denominator: HUNDRED
```

**Key Characteristics:**
- **Immediate Response**: No external dependencies, very fast
- **Memory Efficient**: Minimal memory footprint per route
- **Burst Handling**: Allows bursts up to max_tokens, then steady rate
- **Per-Route Configuration**: Different limits for different endpoints

**SignUp Service Rate Limiting:**
The SignUp service has specific rate limiting configured:
```yaml
- match:
    prefix: "/auth/auth.SignUpService/"
  typed_per_filter_config:
    envoy.filters.http.local_ratelimit:
      token_bucket:
        max_tokens: 50      # Allow bursts of 50 requests
        tokens_per_fill: 50 # Refill 50 tokens per second
        fill_interval: 1s   # Steady state: 50 requests/second
```

### Application-Level Algorithms

#### Fixed Window Algorithm

The fixed window algorithm divides time into fixed intervals and counts requests within each window.

**Key Characteristics:**
- Simple and memory efficient
- Potential for burst traffic at window boundaries
- Predictable reset times

**Lua Script Logic:**
```lua
-- Calculate current window start time
local window_start = math.floor(current_time / window_seconds) * window_seconds
local window_key = key .. ':' .. tostring(window_start)

-- Increment counter for current window
local count = redis.call('INCR', window_key)
if count == 1 then
    redis.call('EXPIRE', window_key, window_seconds)
end

-- Check if limit exceeded
if count <= max_requests then
    return {0, 0}  -- Allow request
else
    -- Calculate retry after time
    local next_window = window_start + window_seconds
    local retry_after = next_window - current_time
    return {1, retry_after}  -- Reject with retry time
end
```

#### Sliding Window Algorithm

The sliding window algorithm maintains a rolling window of requests using sorted sets.

**Key Characteristics:**
- More accurate rate limiting
- Prevents burst traffic at boundaries
- Higher memory usage due to request tracking

**Lua Script Logic:**
```lua
-- Remove expired requests from sliding window
local trim_time = current_time - window_seconds
redis.call('ZREMRANGEBYSCORE', key, 0, trim_time)

-- Count current requests in window
local request_count = redis.call('ZCARD', key)

if request_count < max_requests then
    -- Add current request to window
    redis.call('ZADD', key, current_time, unique_request_id)
    redis.call('EXPIRE', key, window_seconds)
    return {0, 0}  -- Allow request
else
    -- Calculate retry after based on oldest request
    local oldest_requests = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
    local oldest_time = tonumber(oldest_requests[2])
    local retry_after = math.ceil(oldest_time + window_seconds - current_time)
    return {1, retry_after}  -- Reject with retry time
end
```

## Configuration

### Envoy Configuration

#### Global Rate Limiting Filter

The Envoy proxy includes a global local rate limiting filter in the HTTP filter chain:

```yaml
# In envoy.yaml
http_filters:
  - name: envoy.filters.http.local_ratelimit
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
      stat_prefix: http_local_rate_limiter
```

#### Per-Route Rate Limiting

Specific routes can override the global rate limiting configuration:

```yaml
# In envoy.rds.yaml
routes:
  - match:
      prefix: "/auth/auth.SignUpService/"
    route:
      cluster: auth_cluster
      prefix_rewrite: "/auth.SignUpService/"
    typed_per_filter_config:
      envoy.filters.http.local_ratelimit:
        "@type": type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
        stat_prefix: http_local_rate_limiter
        token_bucket:
          max_tokens: 50
          tokens_per_fill: 50
          fill_interval: 1s
        filter_enabled:
          default_value:
            numerator: 100
            denominator: HUNDRED
        filter_enforced:
          default_value:
            numerator: 100
            denominator: HUNDRED
```

#### Environment-Specific Configuration

Rate limiting can be configured differently per environment by modifying the Envoy configuration templates:

```bash
# Development - More permissive
max_tokens: 100
tokens_per_fill: 100

# Production - More restrictive  
max_tokens: 50
tokens_per_fill: 50

# Staging - Balanced
max_tokens: 75
tokens_per_fill: 75
```

### Application Rate Limiting Methods

The system provides several convenience methods for different rate limiting scenarios:

#### By User Identity
```csharp
// Fixed window rate limiting by authenticated user
await context.EnforceFixedByIdentityAsync(
    windowSeconds: 60,    // 1 minute window
    maxRequests: 10,      // 10 requests per window
    requestPath: "/signup" // Optional path-specific limiting
);
```

#### By Email Address
```csharp
// Rate limit by email address (useful for signup/verification)
await context.EnforceFixedByEmailAsync(
    email: "user@example.com",
    windowSeconds: 3600,  // 1 hour window
    maxRequests: 5,       // 5 requests per hour
    requestPath: "/verify"
);
```

#### By IP Address
```csharp
// Rate limit by client IP address
await context.EnforceFixedByIpAsync(
    windowSeconds: 300,   // 5 minute window
    maxRequests: 20,      // 20 requests per 5 minutes
    requestPath: "/login"
);
```

### Key Generation Strategy

Rate limiting keys are generated using a hierarchical structure:

```text
{algorithm}:{path}:{identifier_type}:{identifier_value}
```

Examples:
- `fixed:/signup:email:user@example.com`
- `sliding:/login:user:auth0|12345`
- `fixed:ip:192.168.1.100`

## Usage

### Envoy Rate Limiting

Envoy rate limiting is automatically applied based on the route configuration. No code changes are required in the application.

**Rate Limiting Headers:**
When Envoy rate limiting is triggered, it returns:
- **HTTP Status**: 429 Too Many Requests
- **Headers**: Standard rate limiting headers (if configured)

**Monitoring:**
Envoy exposes rate limiting metrics:
```text
envoy_http_local_rate_limiter_enabled: Total requests evaluated
envoy_http_local_rate_limiter_enforced: Total requests rate limited
envoy_http_local_rate_limiter_rate_limited: Total requests blocked
```

### Application Rate Limiting

#### Basic Implementation

```csharp
public class SignUpService : SignUpServiceBase
{
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(
        InitiateSignUpRequest request, 
        ServerCallContext context)
    {
        var httpContext = context.GetHttpContext();
        
        // Apply rate limiting by email address
        await httpContext.EnforceFixedByEmailAsync(
            request.EmailAddress, 
            windowSeconds: 3600,  // 1 hour
            maxRequests: 15,      // 15 signup attempts per hour
            cancellationToken: context.CancellationToken
        );

        // Process signup logic...
    }
}
```

### Advanced Usage with Custom Paths

```csharp
// Rate limit verification code requests separately
private static async Task EnforceVerificationCodeLimit(
    HttpContext context, 
    string emailAddress, 
    CancellationToken cancellationToken)
{
    var verificationCodePath = "SignUpService.ResendVerificationCode";
    
    await context.EnforceFixedByEmailAsync(
        emailAddress,
        windowSeconds: 3600,  // 1 hour
        maxRequests: 5,       // 5 verification codes per hour
        requestPath: verificationCodePath,
        cancellationToken: cancellationToken
    );
}
```

## Testing

### Envoy Rate Limiting Tests

#### Load Testing

```bash
# Test Envoy rate limiting with curl
for i in {1..60}; do
  curl -w "%{http_code}\n" -o /dev/null -s \
    https://localhost:443/auth/auth.SignUpService/InitiateSignUp \
    -H "Content-Type: application/grpc-web+proto" \
    -d "test-data"
done

# Expected: First 50 requests return 200, subsequent requests return 429
```

#### Integration Testing

```typescript
describe('Envoy Rate Limiting', () => {
  it('should rate limit after exceeding token bucket', async () => {
    const promises = [];
    
    // Send 60 concurrent requests (exceeds 50 token limit)
    for (let i = 0; i < 60; i++) {
      promises.push(
        signUpClient.initiateSignUp({ emailAddress: `test${i}@example.com` })
          .catch(error => error)
      );
    }
    
    const results = await Promise.all(promises);
    const rateLimited = results.filter(r => 
      r.code === grpc.status.RESOURCE_EXHAUSTED
    );
    
    expect(rateLimited.length).toBeGreaterThan(0);
  });
});
```

### Application Rate Limiting Tests

#### Unit Tests

Rate limiting functionality can be tested using Redis test containers:

```csharp
[Test]
public async Task EnforceFixedByEmail_ExceedsLimit_ThrowsResourceExhausted()
{
    // Arrange
    var email = "test@example.com";
    var maxRequests = 3;
    var windowSeconds = 60;

    // Act & Assert
    for (int i = 0; i < maxRequests; i++)
    {
        await context.EnforceFixedByEmailAsync(email, windowSeconds, maxRequests);
    }

    // This should throw ResourceExhausted
    var exception = await Assert.ThrowsAsync<RpcException>(
        () => context.EnforceFixedByEmailAsync(email, windowSeconds, maxRequests)
    );
    
    Assert.That(exception.StatusCode, Is.EqualTo(StatusCode.ResourceExhausted));
}
```

### Integration Tests

```csharp
[Test]
public async Task SignUp_RateLimitExceeded_ReturnsResourceExhausted()
{
    var email = "test@example.com";
    
    // Make requests up to the limit
    for (int i = 0; i < 15; i++)
    {
        var response = await signUpClient.InitiateSignUpAsync(
            new InitiateSignUpRequest { EmailAddress = email }
        );
        Assert.That(response, Is.Not.Null);
    }

    // Next request should be rate limited
    var exception = await Assert.ThrowsAsync<RpcException>(
        () => signUpClient.InitiateSignUpAsync(
            new InitiateSignUpRequest { EmailAddress = email }
        )
    );
    
    Assert.That(exception.StatusCode, Is.EqualTo(StatusCode.ResourceExhausted));
    Assert.That(exception.Trailers.GetValue("retry-after-seconds"), Is.Not.Null);
}
```

## Troubleshooting

### Envoy Rate Limiting Issues

#### Rate Limiting Not Working
- **Cause**: Local rate limiter filter not configured in HTTP filter chain
- **Solution**: Ensure `envoy.filters.http.local_ratelimit` is in the filter chain
- **Check**: Verify Envoy admin interface shows the filter is loaded

#### Inconsistent Rate Limiting
- **Cause**: Multiple Envoy instances with separate token buckets
- **Solution**: Consider using global rate limiting with external rate limit service
- **Monitor**: Check Envoy metrics for rate limiting decisions

#### Rate Limits Too Restrictive
- **Cause**: Token bucket configuration too low for expected traffic
- **Solution**: Adjust `max_tokens` and `tokens_per_fill` values
- **Analysis**: Monitor Envoy rate limiting metrics to tune appropriately

#### Configuration Not Applied
- **Cause**: Route-specific configuration syntax errors
- **Solution**: Validate YAML syntax and Envoy configuration
- **Debug**: Check Envoy admin interface for configuration errors

### Application Rate Limiting Issues

#### Common Issues

#### Rate Limit Not Applied
- **Cause**: Redis connection not configured
- **Solution**: Ensure Redis is running and connection string is correct
- **Check**: Verify `IConnectionMultiplexer` is registered in DI container

#### Inconsistent Rate Limiting
- **Cause**: Multiple Redis instances or clock skew
- **Solution**: Use single Redis instance for rate limiting
- **Check**: Ensure all services connect to same Redis instance

#### High Memory Usage
- **Cause**: Sliding window algorithm with high traffic
- **Solution**: Consider using fixed window for high-traffic endpoints
- **Monitor**: Track Redis memory usage and key expiration

### Error Messages

Rate limit exceeded errors include helpful information:

```csharp
// Exception includes retry-after metadata
var retryAfterSeconds = exception.Trailers.GetValue("retry-after-seconds");
var message = $"Rate limit exceeded. Try again in {Math.Ceiling(retryAfterSeconds / 60.0)} minutes.";
```

### Monitoring and Observability

#### Envoy Metrics

Envoy exposes comprehensive rate limiting metrics:

```text
# Token bucket metrics
envoy_http_local_rate_limiter_enabled{}: Requests evaluated for rate limiting
envoy_http_local_rate_limiter_enforced{}: Requests where rate limiting was enforced  
envoy_http_local_rate_limiter_rate_limited{}: Requests that were rate limited

# Per-route metrics (with route labels)
envoy_http_local_rate_limiter_enabled{route="auth_signup"}: SignUp service specific metrics
```

#### Application Metrics

Application-level rate limiting operations are instrumented with OpenTelemetry:

```csharp
activity?.SetTag("rate.limit.key", key);
activity?.SetTag("rate.limit.algorithm", "fixed");
activity?.SetTag("rate.limit.allowed", allowed);
activity?.SetTag("rate.limit.retry_after", retryAfter);
```

#### Monitoring Dashboard

Key metrics to monitor:
- **Envoy Rate Limit Hit Rate**: Percentage of requests rate limited at gateway
- **Application Rate Limit Hit Rate**: Percentage of requests rate limited at application
- **Rate Limit Effectiveness**: Comparison of gateway vs application rate limiting
- **Token Bucket Utilization**: How often the token bucket is depleted

## Related Features

- [Error Handling](error-handling.md) - How rate limit errors are processed
- [JWT Validation](jwt-validation.md) - User identity extraction for rate limiting
- [CORS Configuration](cors-configuration.md) - Cross-origin request handling