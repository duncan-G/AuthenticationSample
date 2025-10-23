# gRPC Services

## Overview

The system uses gRPC as the primary communication protocol between frontend and backend services. gRPC provides type-safe, high-performance communication with automatic code generation for multiple languages. The architecture includes .NET gRPC services on the backend and gRPC-Web clients on the frontend, connected through an Envoy proxy that handles protocol translation.

## Architecture

### Service Architecture

The gRPC services follow a clean architecture pattern with clear separation of concerns:

```text
Auth.Grpc/                    # gRPC API layer
├── Services/                 # gRPC service implementations
│   ├── SignUpService.cs     # User registration service
│   └── AuthorizationService.cs # Authorization checks
├── Protos/                  # Protocol buffer definitions
│   ├── sign-up.proto        # Sign-up service contract
│   └── authz.proto          # Authorization service contract
└── Validators/              # Request validation logic
```

### Service Communication Flow

1. **Frontend Client** → gRPC-Web request
2. **Envoy Proxy** → Protocol translation (gRPC-Web to gRPC)
3. **Backend Service** → Business logic processing
4. **Response** → Flows back through the same path

## SignUpService Implementation

### Service Definition

The `SignUpService` handles user registration workflows with three main operations:

```csharp
public class SignUpService : Protos.SignUpService.SignUpServiceBase
{
    // Initiates user sign-up process
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(
        InitiateSignUpRequest request, ServerCallContext context)
    
    // Verifies sign-up and signs in user
    public override async Task<VerifyAndSignInResponse> VerifyAndSignInAsync(
        VerifyAndSignInRequest request, ServerCallContext context)
    
    // Resends verification code
    public override async Task<Empty> ResendVerificationCodeAsync(
        ResendVerificationCodeRequest request, ServerCallContext context)
}
```

### Key Features

#### Rate Limiting Integration
- **Email-based rate limiting**: Prevents abuse by limiting requests per email address
- **IP-based rate limiting**: Additional protection at the network level
- **Method-specific limits**: Different limits for different operations

```csharp
// Fixed window rate limiting by email
await httpContext
    .EnforceFixedByEmailAsync(request.EmailAddress, 3600, 15, 
        cancellationToken: context.CancellationToken)
    .ConfigureAwait(false);
```

#### Session Management
- **HTTP-only cookies**: Secure token storage
- **Dual token system**: Access and refresh tokens
- **Automatic expiry**: Tokens include expiration timestamps

```csharp
var accessTokenCookie = 
    $"AT_SID={clientSession.AccessTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={clientSession.AccessTokenExpiry.ToUniversalTime():R}";
```

#### Error Handling
- **Structured logging**: Comprehensive request/response logging
- **Exception translation**: gRPC status codes for different error types
- **Client-friendly errors**: Meaningful error messages for frontend

### Business Logic Integration

The service integrates with core business logic through dependency injection:

- **IIdentityService**: Core authentication operations
- **ISignUpEligibilityGuard**: Business rules enforcement
- **ILogger**: Structured logging

## AuthorizationService

### Purpose
Handles authorization checks for protected resources using the external authorization pattern.

### Implementation
```csharp
public class AuthorizationService : Protos.AuthorizationService.AuthorizationServiceBase
{
    public override async Task<Empty> Check(Empty request, ServerCallContext context)
    {
        // JWT validation and authorization logic
        // Returns success/failure for Envoy to allow/deny requests
    }
}
```

### Integration with Envoy
- **External Authorization Filter**: Envoy calls this service for protected routes
- **JWT Validation**: Validates access tokens from cookies
- **Context Propagation**: Passes user context to downstream services

## Greeter Service (Example)

### Purpose
Demonstrates basic gRPC service implementation and serves as a template for new services.

### Implementation
```csharp
public class GreeterService : Greeter.GreeterBase
{
    public override Task<HelloReply> SayHello(HelloRequest request, ServerCallContext context)
    {
        return Task.FromResult(new HelloReply
        {
            Message = "Hello " + request.Name
        });
    }
}
```

## Configuration

### Service Registration
Services are registered in `Program.cs` with dependency injection:

```csharp
builder.Services.AddGrpc(options =>
{
    options.Interceptors.Add<ValidationInterceptor>();
    options.Interceptors.Add<ExceptionsInterceptor>();
});

// Register gRPC services
builder.Services.AddScoped<SignUpService>();
```

### Interceptors
- **ValidationInterceptor**: Validates incoming requests
- **ExceptionsInterceptor**: Handles exceptions and converts to gRPC status codes

### Health Checks
gRPC services include health check endpoints for monitoring:

```csharp
app.MapGrpcService<HealthService>();
```

## Testing

### Unit Testing
- **Service logic testing**: Test business logic without gRPC infrastructure
- **Mock dependencies**: Use dependency injection for testable code
- **Validation testing**: Test request validation logic

### Integration Testing
- **gRPC client testing**: Test actual gRPC communication
- **End-to-end flows**: Test complete user workflows
- **Error scenario testing**: Test error handling and edge cases

Example integration test:
```csharp
[Test]
public async Task InitiateSignUpAsync_ValidRequest_ReturnsExpectedResponse()
{
    // Arrange
    var client = CreateTestClient();
    var request = new InitiateSignUpRequest
    {
        EmailAddress = "test@example.com",
        RequirePassword = true
    };

    // Act
    var response = await client.InitiateSignUpAsync(request);

    // Assert
    Assert.That(response.NextStep, Is.EqualTo(SignUpStep.PasswordRequired));
}
```

## Performance Considerations

### Connection Management
- **HTTP/2 multiplexing**: Multiple requests over single connection
- **Connection pooling**: Efficient connection reuse
- **Keep-alive settings**: Optimized for long-lived connections

### Serialization
- **Protocol Buffers**: Efficient binary serialization
- **Schema evolution**: Backward/forward compatibility
- **Compression**: Built-in gRPC compression support

### Monitoring
- **OpenTelemetry integration**: Distributed tracing
- **Metrics collection**: Request/response metrics
- **Health monitoring**: Service health endpoints

## Security

### Transport Security
- **TLS encryption**: All gRPC communication encrypted
- **Certificate validation**: Mutual TLS authentication
- **SNI support**: Server Name Indication for proper routing

### Authentication
- **JWT tokens**: Stateless authentication
- **Cookie-based sessions**: Secure token storage
- **Token validation**: Comprehensive token verification

### Authorization
- **Role-based access**: User role validation
- **Resource-based access**: Fine-grained permissions
- **External authorization**: Envoy integration for centralized auth

## Troubleshooting

### Common Issues

#### Connection Problems
- **Certificate errors**: Check TLS certificate configuration
- **Port conflicts**: Verify service ports are available
- **Network connectivity**: Test direct service connectivity

#### Performance Issues
- **Connection pooling**: Monitor connection pool usage
- **Serialization overhead**: Profile message serialization
- **Database queries**: Optimize underlying data access

#### Authentication Failures
- **Token expiry**: Check token expiration handling
- **Cookie settings**: Verify cookie security settings
- **JWT validation**: Debug token validation logic

### Debugging Tools
- **gRPC reflection**: Service discovery and testing
- **Envoy admin interface**: Proxy configuration and stats
- **OpenTelemetry traces**: Distributed request tracing

### Logging
Services include comprehensive logging for troubleshooting:

```csharp
logger.LogInformation("Starting sign up for {EmailAddress}", request.EmailAddress);
logger.LogWarning("Rate limit exceeded for {EmailAddress}", emailAddress);
logger.LogError(ex, "Sign up failed for {EmailAddress}", request.EmailAddress);
```

## Related Features

- [Protocol Buffer Definitions](protocol-buffers.md) - Message structure definitions
- [gRPC-Web Client Integration](grpc-web-client.md) - Frontend client implementation
- [API Gateway Configuration](api-gateway.md) - Envoy proxy setup
- [Rate Limiting](../security/rate-limiting.md) - Request rate limiting
- [JWT Validation](../security/jwt-validation.md) - Token validation