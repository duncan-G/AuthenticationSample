# JWT Validation and Token Security

## Overview

The authentication system implements robust JWT (JSON Web Token) validation using OpenID Connect standards. The system validates tokens against AWS Cognito's public keys, ensures proper audience and issuer validation, and provides secure token handling throughout the application lifecycle.

## Implementation

### Architecture

The JWT validation system consists of several key components:

- **TokenValidationParametersHelper**: Manages OIDC discovery and token validation parameters
- **AuthenticationServiceCollectionExtensions**: Configures JWT Bearer authentication
- **AuthOptions**: Configuration for authority and audience settings
- **SessionData**: Secure session management with token storage

### Token Validation Process

#### 1. OIDC Discovery

The system automatically discovers JWT validation parameters from the OpenID Connect provider:

```csharp
public sealed class TokenValidationParametersHelper
{
    private readonly ConfigurationManager<OpenIdConnectConfiguration> _configurationManager;

    public TokenValidationParametersHelper(IOptions<AuthOptions> options)
    {
        var authority = options.Value.Authority?.TrimEnd('/');
        var metadataAddress = $"{authority}/.well-known/openid-configuration";

        _configurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
            metadataAddress,
            new OpenIdConnectConfigurationRetriever(),
            new HttpDocumentRetriever { RequireHttps = true }
        )
        {
            AutomaticRefreshInterval = TimeSpan.FromHours(12),
            RefreshInterval = TimeSpan.FromHours(1)
        };
    }
}
```

#### 2. Token Validation Parameters

The system configures comprehensive token validation:

```csharp
public async Task<TokenValidationParameters> GetTokenValidationParameters(CancellationToken ct = default)
{
    var discoveryDocument = await _configurationManager.GetConfigurationAsync(ct);

    return new TokenValidationParameters
    {
        ValidateIssuerSigningKey = true,
        IssuerSigningKeys = discoveryDocument.SigningKeys,

        ValidateIssuer = true,
        ValidIssuer = discoveryDocument.Issuer,

        ValidateAudience = false, // Configured for multi-audience scenarios

        ValidateLifetime = true,
        ClockSkew = TimeSpan.FromSeconds(60) // Allow 60 seconds clock skew
    };
}
```

### Security Features

#### Signature Validation
- **RSA256 Algorithm**: Uses RSA256 for token signature verification
- **Key Rotation**: Automatically handles JWT signing key rotation
- **HTTPS Requirement**: Enforces HTTPS for metadata retrieval

#### Lifetime Validation
- **Expiration Check**: Validates `exp` claim against current time
- **Not Before Check**: Validates `nbf` claim if present
- **Clock Skew Tolerance**: Allows 60 seconds tolerance for time differences

#### Issuer Validation
- **Dynamic Discovery**: Uses issuer from OIDC discovery document
- **Exact Match**: Requires exact issuer match for security

## Configuration

### Authentication Setup

```csharp
public static IServiceCollection AddAuthnAuthz(
    this IServiceCollection services,
    Action<AuthOptions> configureOptions)
{
    services
        .Configure(configureOptions)
        .AddSingleton<TokenValidationParametersHelper>();

    services
        .AddAuthentication(options =>
        {
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
            options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
        })
        .AddJwtBearer();

    // Configure JWT Bearer options
    services
        .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
        .Configure<TokenValidationParametersHelper>((jwt, helper) =>
        {
            jwt.RequireHttpsMetadata = true;
            jwt.SaveToken = false; // Don't store tokens in AuthenticationProperties
            jwt.TokenValidationParameters = helper.GetTokenValidationParameters().GetAwaiter().GetResult();
        });

    return services;
}
```

### Application Configuration

```csharp
// In Program.cs or Startup.cs
services.AddAuthnAuthz(options =>
{
    options.Authority = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXXX";
    options.Audience = "your-client-id";
});
```

### Environment Configuration

```bash
# .env configuration
AUTH_AUTHORITY=https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXXXXXX
AUTH_AUDIENCE=your-cognito-client-id
```

## Usage

### Protecting gRPC Services

```csharp
[Authorize] // Requires valid JWT token
public class SecureService : SecureServiceBase
{
    public override async Task<SecureResponse> SecureMethod(
        SecureRequest request, 
        ServerCallContext context)
    {
        // Access user claims from validated token
        var userId = context.GetHttpContext().User.FindFirstValue("sub");
        var email = context.GetHttpContext().User.FindFirstValue("email");
        
        // Method implementation...
    }
}
```

### Extracting User Information

```csharp
public static class ServerCallContextExtensions
{
    public static string? GetUserId(this ServerCallContext context)
    {
        return context.GetHttpContext().User.FindFirstValue("sub");
    }

    public static string? GetUserEmail(this ServerCallContext context)
    {
        return context.GetHttpContext().User.FindFirstValue("email");
    }

    public static bool IsAuthenticated(this ServerCallContext context)
    {
        return context.GetHttpContext().User.Identity?.IsAuthenticated == true;
    }
}
```

### Session Management

The system uses secure HTTP-only cookies for session management:

```csharp
public record SessionData
{
    public required string AccessTokenId { get; init; }
    public required string RefreshTokenId { get; init; }
    public required DateTime AccessTokenExpiry { get; init; }
    public required DateTime RefreshTokenExpiry { get; init; }
}

// Setting secure session cookies
var accessTokenCookie = $"AT_SID={session.AccessTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={session.AccessTokenExpiry:R}";
var refreshTokenCookie = $"RT_SID={session.RefreshTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={session.RefreshTokenExpiry:R}";
```

## Testing

### Unit Tests

```csharp
[Test]
public async Task GetTokenValidationParameters_ValidConfiguration_ReturnsValidParameters()
{
    // Arrange
    var options = Options.Create(new AuthOptions
    {
        Authority = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test",
        Audience = "test-client-id"
    });
    var helper = new TokenValidationParametersHelper(options);

    // Act
    var parameters = await helper.GetTokenValidationParameters();

    // Assert
    Assert.That(parameters.ValidateIssuerSigningKey, Is.True);
    Assert.That(parameters.ValidateIssuer, Is.True);
    Assert.That(parameters.ValidateLifetime, Is.True);
    Assert.That(parameters.ClockSkew, Is.EqualTo(TimeSpan.FromSeconds(60)));
}
```

### Integration Tests

```csharp
[Test]
public async Task SecureEndpoint_ValidToken_ReturnsSuccess()
{
    // Arrange
    var token = await GenerateValidJwtToken();
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

    // Act
    var response = await client.GetAsync("/secure-endpoint");

    // Assert
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.OK));
}

[Test]
public async Task SecureEndpoint_InvalidToken_ReturnsUnauthorized()
{
    // Arrange
    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", "invalid-token");

    // Act
    var response = await client.GetAsync("/secure-endpoint");

    // Assert
    Assert.That(response.StatusCode, Is.EqualTo(HttpStatusCode.Unauthorized));
}
```

## Troubleshooting

### Common Issues

#### Token Validation Fails
- **Cause**: Incorrect authority or audience configuration
- **Solution**: Verify AUTH_AUTHORITY and AUTH_AUDIENCE environment variables
- **Check**: Ensure authority URL matches Cognito User Pool

#### Key Rotation Issues
- **Cause**: Cached signing keys become invalid
- **Solution**: Keys are automatically refreshed every 12 hours
- **Monitor**: Check logs for key refresh failures

#### Clock Skew Problems
- **Cause**: Server time differs significantly from token issuer
- **Solution**: Synchronize server time with NTP
- **Configure**: Adjust ClockSkew tolerance if needed

### Error Messages

Common JWT validation error scenarios:

```csharp
// Invalid signature
"IDX10503: Signature validation failed. Keys tried: '[PII is hidden]'"

// Expired token
"IDX10223: Lifetime validation failed. The token is expired."

// Invalid issuer
"IDX10205: Issuer validation failed. Issuer: '[PII is hidden]'. Did not match: validationParameters.ValidIssuer"
```

### Security Considerations

#### Token Storage
- **Never store tokens in localStorage**: Use HTTP-only cookies
- **Secure transmission**: Always use HTTPS in production
- **Token expiration**: Implement proper token refresh logic

#### Key Management
- **Automatic rotation**: System handles key rotation automatically
- **HTTPS enforcement**: Metadata retrieval requires HTTPS
- **Validation caching**: Keys are cached with appropriate refresh intervals

## Related Features

- [Session Management](../authentication/session-management.md) - Token-based session handling
- [Rate Limiting](rate-limiting.md) - User identification for rate limiting
- [Error Handling](error-handling.md) - Authentication error processing