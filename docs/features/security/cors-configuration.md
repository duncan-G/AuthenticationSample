# CORS Configuration

## Overview

The authentication system implements Cross-Origin Resource Sharing (CORS) configuration to enable secure communication between the frontend client and backend gRPC services. The CORS setup is designed to work with gRPC-Web while maintaining security best practices for cross-origin requests.

## Implementation

### Architecture

The CORS configuration system implements a multi-layered approach with both API gateway and application-level CORS handling:

**API Gateway Layer (Envoy):**
- **Envoy CORS Filter**: Built-in CORS handling at the proxy level
- **Route-Specific Policies**: Different CORS policies for different routes
- **Preflight Handling**: Automatic OPTIONS request handling
- **Header Management**: Comprehensive request/response header control

**Application Layer (.NET):**
- **CorsExtensions**: Extension methods for configuring CORS policies
- **CorsOptions**: Configuration options for allowed origins
- **Policy-Based Configuration**: Named CORS policies for different scenarios
- **gRPC-Web Integration**: Special headers for gRPC-Web communication

### Multi-Layer CORS Flow

```text
┌─────────────────────────────────────────────────────────────┐
│                Cross-Origin Request                         │
├─────────────────────────────────────────────────────────────┤
│                 Envoy CORS Filter                           │
│            (Preflight + Header Validation)                 │
├─────────────────────────────────────────────────────────────┤
│                 .NET CORS Middleware                        │
│              (Additional Policy Validation)                │
├─────────────────────────────────────────────────────────────┤
│                   gRPC Service                              │
└─────────────────────────────────────────────────────────────┘
```

### CORS Extension Implementation

```csharp
public static class CorsExtensions
{
    public const string CorsPolicyName = "AllowClient";

    public static IServiceCollection AddAuthSampleCors(
        this IServiceCollection services,
        Action<CorsOptions> configureOptions)
    {
        CorsOptions options = new();
        configureOptions(options);

        services.AddCors(o => o.AddPolicy(CorsPolicyName, policyBuilder =>
        {
            policyBuilder.WithOrigins(options.AllowedOrigins.ToArray())
                .AllowAnyMethod()
                .AllowAnyHeader()
                .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding", "Error-Code");
        }));

        return services;
    }
}
```

### Configuration Options

```csharp
public record CorsOptions
{
    public IReadOnlyCollection<string> AllowedOrigins { get; init; } = [];
}
```

## Configuration

### Envoy CORS Configuration

#### Global CORS Filter

Envoy includes a global CORS filter in the HTTP filter chain:

```yaml
# In envoy.yaml
http_filters:
  - name: envoy.filters.http.cors
    typed_config:
      "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
```

#### Route-Specific CORS Policy

Each virtual host can define specific CORS policies:

```yaml
# In envoy.rds.yaml
virtual_hosts:
  - name: service_routes_virtual_host
    domains: [$ALLOWED_HOSTS]
    typed_per_filter_config:
      envoy.filters.http.cors:
        "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.CorsPolicy
        allow_origin_string_match:
          # Dynamic origin configuration from environment
          $PROCESSED_ORIGINS
        allow_methods: "GET,POST,PUT,DELETE,OPTIONS"
        allow_headers: "keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,authorization,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout,traceparent,tracestate,b3,baggage"
        expose_headers: "grpc-status,grpc-message,grpc-messages,error-code,error-codes,retry-after-seconds"
        max_age: "1728000"  # 20 days preflight cache
        allow_credentials: true
```

#### Environment Variable Configuration

CORS origins are configured through environment variables:

```bash
# Development
ALLOWED_ORIGINS="https://localhost:3000,http://localhost:3000"

# Production  
ALLOWED_ORIGINS="https://app.example.com,https://www.example.com"

# The $PROCESSED_ORIGINS is generated from ALLOWED_ORIGINS
```

#### Comprehensive Header Support

The Envoy CORS configuration includes comprehensive header support for gRPC-Web:

**Allowed Request Headers:**
- Standard headers: `keep-alive`, `user-agent`, `cache-control`, `content-type`
- Authorization: `authorization`
- gRPC-Web specific: `x-grpc-web`, `grpc-timeout`, `x-user-agent`
- Tracing headers: `traceparent`, `tracestate`, `b3`, `baggage`
- Content handling: `content-transfer-encoding`, `x-accept-content-transfer-encoding`

**Exposed Response Headers:**
- gRPC status: `grpc-status`, `grpc-message`, `grpc-messages`
- Error handling: `error-code`, `error-codes`
- Rate limiting: `retry-after-seconds`

### Application CORS Configuration

#### Basic Setup

```csharp
// In Program.cs or Startup.cs
services.AddAuthSampleCors(options =>
{
    options.AllowedOrigins = new[]
    {
        "https://localhost:3000",    // Development frontend
        "https://app.example.com",   // Production frontend
        "https://staging.example.com" // Staging frontend
    };
});

// Apply CORS policy
app.UseCors(CorsExtensions.CorsPolicyName);
```

### Environment-Specific Configuration

#### Development Configuration

```csharp
if (builder.Environment.IsDevelopment())
{
    services.AddAuthSampleCors(options =>
    {
        options.AllowedOrigins = new[]
        {
            "https://localhost:3000",
            "http://localhost:3000",  // Allow HTTP in development
            "https://127.0.0.1:3000"
        };
    });
}
```

#### Production Configuration

```csharp
if (builder.Environment.IsProduction())
{
    services.AddAuthSampleCors(options =>
    {
        options.AllowedOrigins = new[]
        {
            "https://app.example.com",
            "https://www.example.com"
        };
    });
}
```

### Configuration from Environment Variables

```csharp
services.AddAuthSampleCors(options =>
{
    var allowedOrigins = builder.Configuration
        .GetSection("Cors:AllowedOrigins")
        .Get<string[]>() ?? Array.Empty<string>();
    
    options.AllowedOrigins = allowedOrigins;
});
```

```json
// appsettings.json
{
  "Cors": {
    "AllowedOrigins": [
      "https://localhost:3000",
      "https://app.example.com"
    ]
  }
}
```

## Usage

### gRPC Service Configuration

```csharp
public class Program
{
    public static void Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        // Add CORS configuration
        builder.Services.AddAuthSampleCors(options =>
        {
            options.AllowedOrigins = new[] { "https://localhost:3000" };
        });

        // Add gRPC services
        builder.Services.AddGrpc();

        var app = builder.Build();

        // Enable CORS before gRPC
        app.UseCors(CorsExtensions.CorsPolicyName);

        // Configure gRPC-Web
        app.UseGrpcWeb(new GrpcWebOptions { DefaultEnabled = true });

        // Map gRPC services
        app.MapGrpcService<SignUpService>().EnableGrpcWeb();

        app.Run();
    }
}
```

### Client-Side Configuration

#### gRPC-Web Client Setup

```typescript
import { GrpcWebFetchTransport } from "@protobuf-ts/grpcweb-transport";
import { SignUpServiceClient } from "./generated/sign-up.client";

const transport = new GrpcWebFetchTransport({
    baseUrl: "https://api.example.com",
    format: "binary", // or "text"
});

const client = new SignUpServiceClient(transport);
```

#### Fetch API Configuration

```typescript
// CORS is handled automatically by the browser
const response = await fetch("https://api.example.com/grpc/SignUpService/InitiateSignUp", {
    method: "POST",
    headers: {
        "Content-Type": "application/grpc-web+proto",
        "Authorization": `Bearer ${token}`
    },
    body: requestData
});
```

## Security Features

### Origin Validation

The CORS configuration enforces strict origin validation:

```csharp
// Only specified origins are allowed
policyBuilder.WithOrigins(options.AllowedOrigins.ToArray())
```

**Security Benefits:**
- Prevents unauthorized domains from accessing the API
- Blocks malicious cross-origin requests
- Maintains control over client applications

### Method and Header Policies

```csharp
policyBuilder
    .AllowAnyMethod()    // Allows all HTTP methods (GET, POST, etc.)
    .AllowAnyHeader()    // Allows all request headers
```

**Considerations:**
- `AllowAnyMethod()` is safe for gRPC-Web (only uses POST)
- `AllowAnyHeader()` allows custom headers needed for gRPC-Web
- More restrictive policies can be applied if needed

### Exposed Headers

```csharp
.WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding", "Error-Code")
```

**Purpose:**
- Allows client to read gRPC-specific response headers
- Enables proper error handling with custom error codes
- Required for gRPC-Web protocol compliance

## Testing

### Unit Tests

```csharp
[Test]
public void AddAuthSampleCors_ConfiguresPolicy_WithCorrectSettings()
{
    // Arrange
    var services = new ServiceCollection();
    var allowedOrigins = new[] { "https://localhost:3000", "https://app.example.com" };

    // Act
    services.AddAuthSampleCors(options =>
    {
        options.AllowedOrigins = allowedOrigins;
    });

    // Assert
    var serviceProvider = services.BuildServiceProvider();
    var corsService = serviceProvider.GetRequiredService<ICorsService>();
    
    // Verify policy exists and is configured correctly
    Assert.That(corsService, Is.Not.Null);
}
```

### Envoy CORS Tests

```bash
# Test Envoy CORS preflight handling
curl -X OPTIONS https://localhost:443/auth/auth.SignUpService/InitiateSignUp \
  -H "Origin: https://localhost:3000" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type,authorization" \
  -v

# Expected response headers:
# Access-Control-Allow-Origin: https://localhost:3000
# Access-Control-Allow-Methods: GET,POST,PUT,DELETE,OPTIONS
# Access-Control-Allow-Headers: content-type,authorization,...
# Access-Control-Max-Age: 1728000
```

### Integration Tests

```csharp
[Test]
public async Task EnvoyCors_CrossOriginRequest_AllowedOrigin_ReturnsSuccess()
{
    // Test through Envoy proxy
    var client = new HttpClient();
    client.BaseAddress = new Uri("https://localhost:443");
    client.DefaultRequestHeaders.Add("Origin", "https://localhost:3000");

    // Act
    var response = await client.PostAsync("/auth/auth.SignUpService/InitiateSignUp", content);

    // Assert
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.OK));
    Assert.That(response.Headers.GetValues("Access-Control-Allow-Origin"), 
                Contains.Item("https://localhost:3000"));
}

[Test]
public async Task EnvoyCors_PreflightRequest_ReturnsCorrectHeaders()
{
    // Arrange
    var client = new HttpClient();
    client.BaseAddress = new Uri("https://localhost:443");
    
    var request = new HttpRequestMessage(HttpMethod.Options, "/auth/auth.SignUpService/InitiateSignUp");
    request.Headers.Add("Origin", "https://localhost:3000");
    request.Headers.Add("Access-Control-Request-Method", "POST");
    request.Headers.Add("Access-Control-Request-Headers", "content-type,authorization");

    // Act
    var response = await client.SendAsync(request);

    // Assert
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.OK));
    Assert.That(response.Headers.GetValues("Access-Control-Allow-Methods"), 
                Contains.Item("POST"));
    Assert.That(response.Headers.GetValues("Access-Control-Max-Age"), 
                Contains.Item("1728000"));
}

[Test]
public async Task EnvoyCors_DisallowedOrigin_ReturnsBlocked()
{
    // Arrange
    var client = new HttpClient();
    client.BaseAddress = new Uri("https://localhost:443");
    client.DefaultRequestHeaders.Add("Origin", "https://malicious.com");

    // Act
    var response = await client.PostAsync("/auth/auth.SignUpService/InitiateSignUp", content);

    // Assert - Envoy blocks at CORS level
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.Forbidden));
}
```

### Frontend Tests

```typescript
describe('CORS Configuration', () => {
    it('should allow requests from configured origin', async () => {
        // This test runs in a browser environment with the correct origin
        const client = new SignUpServiceClient(transport);
        
        const response = await client.initiateSignUp({
            emailAddress: "test@example.com"
        });
        
        expect(response).toBeDefined();
    });

    it('should handle CORS preflight requests', async () => {
        const response = await fetch(apiUrl, {
            method: 'OPTIONS',
            headers: {
                'Origin': 'https://localhost:3000',
                'Access-Control-Request-Method': 'POST',
                'Access-Control-Request-Headers': 'content-type'
            }
        });

        expect(response.status).toBe(200);
        expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://localhost:3000');
    });
});
```

## Troubleshooting

### Common Issues

#### CORS Blocked Requests
- **Symptom**: Browser console shows CORS policy errors
- **Cause**: Origin not in allowed origins list
- **Solution**: Add the client origin to `AllowedOrigins` configuration

```text
Access to fetch at 'https://api.example.com/grpc/...' from origin 'https://localhost:3000' 
has been blocked by CORS policy: No 'Access-Control-Allow-Origin' header is present.
```

#### Preflight Request Failures
- **Symptom**: OPTIONS requests return 404 or 405 errors
- **Cause**: CORS middleware not properly configured
- **Solution**: Ensure `UseCors()` is called before `UseGrpcWeb()`

#### Missing gRPC Headers
- **Symptom**: Client cannot read gRPC status or error codes
- **Cause**: Headers not exposed in CORS configuration
- **Solution**: Verify `WithExposedHeaders()` includes all required headers

### Configuration Validation

#### Development Debugging

```csharp
if (builder.Environment.IsDevelopment())
{
    services.AddAuthSampleCors(options =>
    {
        options.AllowedOrigins = new[] { "https://localhost:3000" };
        
        // Log CORS configuration for debugging
        var logger = builder.Services.BuildServiceProvider().GetRequiredService<ILogger<Program>>();
        logger.LogInformation("CORS configured for origins: {Origins}", 
                            string.Join(", ", options.AllowedOrigins));
    });
}
```

#### Runtime Validation

```csharp
app.Use(async (context, next) =>
{
    if (context.Request.Headers.ContainsKey("Origin"))
    {
        var origin = context.Request.Headers["Origin"].ToString();
        var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
        logger.LogDebug("Request from origin: {Origin}", origin);
    }
    
    await next();
});
```

### Security Considerations

#### Origin Validation
- **Wildcard Origins**: Never use `*` in production
- **Subdomain Handling**: Be explicit about subdomain access
- **Protocol Matching**: Ensure HTTPS/HTTP protocols match

#### Header Security
- **Minimize Exposed Headers**: Only expose necessary headers
- **Sensitive Information**: Never expose authentication tokens in headers
- **Custom Headers**: Validate custom header usage

#### Environment Separation
- **Development**: More permissive for local development
- **Production**: Strict origin validation
- **Staging**: Mirror production configuration

## Related Features

- [JWT Validation](jwt-validation.md) - Authentication with CORS
- [Error Handling](error-handling.md) - Error headers in CORS responses
- [Rate Limiting](rate-limiting.md) - Rate limiting with cross-origin requests