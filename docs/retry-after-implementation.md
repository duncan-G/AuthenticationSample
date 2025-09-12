# Server-Side Retry-After Implementation Guide

This document explains how to send retry-after information from the .NET gRPC server to the client when rate limiting occurs.

## Overview

We've implemented a comprehensive solution that:
1. **Enhanced Redis Scripts**: Modified to return both rate limit status and retry-after time
2. **gRPC Metadata**: Sends retry-after information via gRPC trailers
3. **Client-Side Extraction**: Parses retry-after from gRPC metadata with fallback to message parsing

## Implementation Details

### 1. Enhanced Redis Scripts

The Redis Lua scripts now return an array `{status, retry_after_seconds}` instead of just a status:

#### Fixed Window Script
```lua
-- Returns {0, 0} if allowed, {1, retry_after_seconds} if rate limited
local current_time = redis.call('TIME')
local window_start = math.floor(tonumber(current_time[1]) / @window) * @window
local window_key = @key .. ':' .. tostring(window_start)

local count = redis.call('INCR', window_key)
if count == 1 then
    redis.call('EXPIRE', window_key, @window)
end

if count <= tonumber(@max_requests) then
    return {0, 0}
end

-- Calculate retry after: time until next window
local next_window = window_start + @window
local retry_after = next_window - tonumber(current_time[1])
return {1, retry_after}
```

#### Sliding Window Script
```lua
-- Returns {0, 0} if allowed, {1, retry_after_seconds} if rate limited
local current_time = redis.call('TIME')
local trim_time = tonumber(current_time[1]) - @window
redis.call('ZREMRANGEBYSCORE', @key, 0, trim_time)
local request_count = redis.call('ZCARD', @key)

if request_count < tonumber(@max_requests) then
    redis.call('ZADD', @key, current_time[1], current_time[1] .. current_time[2])
    redis.call('EXPIRE', @key, @window)
    return {0, 0}
end

-- For sliding window, get the oldest request in the window
local oldest_requests = redis.call('ZRANGE', @key, 0, 0, 'WITHSCORES')
if #oldest_requests > 0 then
    local oldest_time = tonumber(oldest_requests[2])
    local retry_after = math.ceil(oldest_time + @window - tonumber(current_time[1]))
    return {1, retry_after}
end
return {1, @window}
```

### 2. Rate Limiter Updates

The `RedisScriptRateLimiter` now extracts both values and provides retry-after via metadata:

```csharp
private async Task<(bool allowed, int retryAfter)> EvaluateScriptAsync(CancellationToken cancellationToken)
{
    // ... existing code ...
    var result = (RedisValue[])await task.ConfigureAwait(false);
    
    var allowed = (int)result[0] == 0;
    var retryAfter = (int)result[1];
    
    return (allowed, retryAfter);
}

private sealed class SimpleLease(bool isAcquired, int retryAfterSeconds = 0) : RateLimitLease
{
    public override bool IsAcquired => isAcquired;
    public override IEnumerable<string> MetadataNames => ["RetryAfter"];

    public override bool TryGetMetadata(string metadataName, out object? metadata)
    {
        if (metadataName == "RetryAfter")
        {
            metadata = retryAfterSeconds;
            return true;
        }
        metadata = null;
        return false;
    }
}
```

### 3. gRPC Error Enhancement

The rate limiting enforcement now adds retry-after information to gRPC trailers:

```csharp
private static async Task EnforceAsync(
    this HttpContext context,
    RateLimiter limiter,
    CancellationToken cancellationToken = default)
{
    using var lease = await limiter.AcquireAsync(1, cancellationToken).ConfigureAwait(false);
    if (!lease.IsAcquired)
    {
        // Extract retry-after information from the lease
        var retryAfterSeconds = 0;
        if (lease.TryGetMetadata("RetryAfter", out var retryAfterObj) && retryAfterObj is int retryAfter)
        {
            retryAfterSeconds = retryAfter;
        }

        // Create error message with retry-after information
        var message = retryAfterSeconds > 0 
            ? $"Rate limit exceeded. Try again in {Math.Ceiling(retryAfterSeconds / 60.0)} minutes."
            : "Rate limit exceeded.";

        var descriptor = new GrpcErrorDescriptor(
            StatusCode.ResourceExhausted,
            ErrorCodes.ResourceExhausted,
            Message: message);
        
        var exception = descriptor.ToRpcException();
        
        // Add retry-after as gRPC metadata
        if (retryAfterSeconds > 0)
        {
            exception.Trailers.Add("retry-after-seconds", retryAfterSeconds.ToString());
        }
        
        throw exception;
    }
}
```

### 4. Envoy Configuration

Envoy must be configured to expose the retry-after header to clients. Update `envoy.rds.yaml`:

```yaml
typed_per_filter_config:
  envoy.filters.http.cors:
    "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
    # ... other CORS settings ...
    expose_headers: "grpc-status,grpc-message,grpc-messages,error-code,error-codes,retry-after-seconds"
```

This allows the client to access the `retry-after-seconds` header when gRPC trailers are converted to HTTP headers by Envoy.

### 5. Client-Side Extraction

The client now extracts retry-after from gRPC metadata with fallback to message parsing:

```typescript
const extractApiError = (err: unknown): { 
    code?: string; 
    serverMessage?: string; 
    retryAfterSeconds?: number 
} => {
    // ... existing code ...
    
    // Extract retry-after-seconds from metadata (gRPC trailers become HTTP headers via Envoy)
    const retryAfterMeta = anyErr.metadata?.["retry-after-seconds"] || anyErr.metadata?.["x-retry-after-seconds"]
    const retryAfterSeconds = typeof retryAfterMeta === "string" 
        ? parseInt(retryAfterMeta, 10) 
        : undefined

    return { code, serverMessage, retryAfterSeconds }
}

export const handleResendApiError = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>,
    onRateLimitExceeded?: (retryAfterMinutes?: number) => void
) => {
    const { code, serverMessage, retryAfterSeconds } = extractApiError(err)

    if (code === ErrorCodes.ResourceExhausted) {
        // Use retry-after from gRPC metadata first, then fallback to parsing server message
        let retryAfterMinutes: number | undefined
        
        if (retryAfterSeconds && retryAfterSeconds > 0) {
            retryAfterMinutes = Math.ceil(retryAfterSeconds / 60)
        } else {
            // Fallback: try to extract retry-after information from server message
            const retryAfterMatch = serverMessage?.match(/(\d+)\s*minutes?/i)
            retryAfterMinutes = retryAfterMatch ? parseInt(retryAfterMatch[1], 10) : undefined
        }
        
        onRateLimitExceeded?.(retryAfterMinutes)
    }
    // ... rest of error handling
}
```

### 6. Refactored Error Handling Architecture

The error handling has been refactored to reduce redundancy and improve composability:

```typescript
// Utility functions for error processing
type ApiErrorInfo = {
    code?: string;
    serverMessage?: string;
    retryAfterSeconds?: number;
};

const extractApiError = (err: unknown): ApiErrorInfo => {
    // Extracts error information including retry-after from both header formats
};

const resolveFriendlyMessage = (code?: string): string => {
    // Maps error codes to user-friendly messages
};

const getRetryAfterMinutes = ({ retryAfterSeconds, serverMessage }) => {
    // Converts retry-after to minutes with fallback to message parsing
};

// Public APIs
export const handleApiError = (err, setErrorMessage, step) => {
    // Standard error handling for all API errors
};

export const handleApiErrorWithRateLimit = (
    err, setErrorMessage, step, onRateLimitExceeded, 
    { rateLimitMessage = "Custom message" } = {}
) => {
    // Enhanced error handling with rate limit callback and custom messaging
};

// Legacy alias for backward compatibility
export const handleResendApiError = (...args) => {
    return handleApiErrorWithRateLimit(...args);
};
```

**Benefits of the refactored approach:**
- **Reduced Redundancy**: Common logic extracted into utility functions
- **Composable**: Mix and match error handling behaviors
- **Customizable**: Override rate limit messages per use case
- **Backward Compatible**: Legacy function still works
- **Testable**: Each utility function can be tested independently

## Usage Examples

### Fixed Window Rate Limiting (5 requests per hour)
```csharp
await httpContext.EnforceFixedByEmailAsync(email, 3600, 5);
```

**Behavior:**
- Allows 5 requests per hour window
- When rate limited, returns exact seconds until next hour window
- Example: If rate limited at 14:30, retry-after = 1800 seconds (30 minutes until 15:00)

### Sliding Window Rate Limiting (10 requests per 60 seconds)
```csharp
await httpContext.EnforceFixedByEmailAsync(email, 60, 10);
```

**Behavior:**
- Allows 10 requests in any 60-second sliding window
- When rate limited, returns seconds until oldest request expires
- Example: If oldest request was 45 seconds ago, retry-after = 15 seconds

## Client-Side Display

The client automatically displays retry-after information:

```typescript
// Rate limited without specific time
"Rate limit exceeded. Please wait before trying again."

// Rate limited with specific time from server
"Rate limit exceeded. Try again in 30 minutes."
```

## Benefits

1. **Precise Timing**: Users know exactly when they can retry
2. **Better UX**: No guessing when rate limits reset
3. **Reduced Server Load**: Users don't retry too early
4. **Graceful Degradation**: Falls back to message parsing if metadata unavailable
5. **Standards Compliant**: Uses gRPC metadata similar to HTTP Retry-After header

## Testing

The implementation includes comprehensive tests covering:
- gRPC metadata extraction
- Fallback to message parsing
- Different rate limiting scenarios
- Client-side display logic

All tests pass and verify the complete retry-after flow from server to client.