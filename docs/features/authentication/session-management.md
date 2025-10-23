# Session Management

## Overview

The session management system provides secure, scalable user session handling with JWT tokens, automatic refresh capabilities, and distributed session storage. It implements industry-standard security practices including HttpOnly cookies, token rotation, and comprehensive session validation.

## Implementation

### Session Architecture

**Dual-Token System**
- **Access Tokens**: Short-lived JWT tokens (typically 15-60 minutes)
- **Refresh Tokens**: Long-lived opaque tokens (typically 30 days)
- **Session IDs**: Opaque identifiers for Redis-cached session data
- **Secure Cookies**: HttpOnly, Secure, SameSite cookies for token storage

### Frontend Session Handling

**Middleware Authentication** (`clients/auth-sample/src/middleware.ts`)
- Automatic session validation on protected routes
- Transparent token refresh when access tokens expire
- Secure cookie management and extraction
- Authentication state propagation to components

**Session Resolution Flow**
```typescript
// Middleware session check
const authResult = await checkAuthentication(
  authServiceUrl,
  middlewareSpan,
  { cookie: cookieHeader }
);

if (isProtected && !authResult.isAuthenticated) {
  return NextResponse.redirect(createSignInRedirectUrl(request.url, pathname));
}
```

### Backend Session Management

**Session Data Structure** (`libraries/Authentication/src/SessionData.cs`)
```csharp
public sealed record SessionData(
    DateTime IssuedAt,
    string AccessToken,
    string IdToken,
    DateTime AccessTokenExpiry,
    string RefreshToken,
    DateTime RefreshTokenExpiry,
    string Sub,
    string Email
);
```

**Session Resolution Service** (`microservices/Auth/src/Auth.Core/Identity/IdentityService.cs`)
- `ResolveSessionAsync`: Validates access tokens and handles refresh
- Redis-based session caching for performance
- Automatic token refresh with rotation
- Comprehensive error handling and logging

**Token Validation** (`libraries/Authentication/src/TokenValidationParametersHelper.cs`)
- JWKS-based signature validation
- Issuer and audience validation
- Configurable clock skew tolerance
- Automatic key rotation support

## Configuration

### JWT Configuration
```csharp
// Token validation parameters
{
  ValidateIssuerSigningKey: true,
  IssuerSigningKeys: discoveryDocument.SigningKeys,
  ValidateIssuer: true,
  ValidIssuer: discoveryDocument.Issuer,
  ValidateAudience: false,
  ValidateLifetime: true,
  ClockSkew: TimeSpan.FromSeconds(60)
}
```

### Cookie Configuration
```csharp
// Secure cookie settings
var accessTokenCookie = $"AT_SID={sessionId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={expiry:R}";
var refreshTokenCookie = $"RT_SID={refreshId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={expiry:R}";
```

### Redis Session Storage
- Session data cached with automatic expiration
- Distributed storage for horizontal scaling
- Efficient serialization with System.Text.Json
- Connection pooling and retry logic

## Usage

### Session Creation Flow
1. User completes authentication (signin/signup)
2. System generates access and refresh tokens
3. Session data is cached in Redis with expiration
4. Secure cookies are set with session identifiers
5. User is redirected to protected application

### Session Validation Flow
1. Middleware extracts session cookies from request
2. Access token is validated against JWKS
3. If valid, request proceeds to protected resource
4. If expired, automatic refresh is attempted
5. If refresh fails, user is redirected to signin

### Token Refresh Flow
1. Access token expires during request
2. System extracts refresh token from secure cookie
3. Refresh token is validated and used to get new tokens
4. New session data is cached in Redis
5. Updated cookies are sent to client
6. Request proceeds with new access token

### Session Termination
1. User initiates logout or session expires
2. Session data is removed from Redis cache
3. Refresh token is revoked in identity provider
4. Cookies are cleared with expired dates
5. User is redirected to public area

## Testing

### Session Lifecycle Tests
```csharp
[Test]
public async Task Should_Refresh_Expired_Access_Token()
{
    // Arrange: Create session with expired access token
    var expiredSession = CreateExpiredSession();
    
    // Act: Attempt to resolve session
    var result = await identityService.ResolveSessionAsync(cookieHeader);
    
    // Assert: Session should be refreshed
    Assert.That(result.IsRefreshed, Is.True);
    Assert.That(result.SessionData.AccessToken, Is.Not.EqualTo(expiredSession.AccessToken));
}
```

### Security Tests
- Token signature validation
- Cookie security attribute enforcement
- Session hijacking prevention
- Cross-site request forgery protection

### Performance Tests
- Redis session cache performance
- Token validation latency
- Concurrent session handling
- Memory usage optimization

## Troubleshooting

### Common Issues

**Session Expiration Problems**
- Check access token expiration times
- Verify refresh token is still valid
- Ensure Redis connectivity for session cache
- Validate JWKS endpoint accessibility

**Cookie Issues**
- Verify Secure flag is set for HTTPS
- Check SameSite attribute compatibility
- Ensure HttpOnly prevents XSS attacks
- Validate cookie domain and path settings

**Token Validation Failures**
- Check JWT signature validation
- Verify issuer and audience claims
- Ensure clock synchronization between services
- Validate JWKS key rotation handling

### Error Scenarios
- `SecurityTokenExpiredException`: Access token expired, refresh attempted
- `SecurityTokenValidationException`: Invalid token signature or claims
- `RefreshTokenExpiredException`: Refresh token expired, re-authentication required
- `SessionNotFoundException`: Session not found in cache, re-authentication required

### Monitoring and Metrics
- Track session creation and termination rates
- Monitor token refresh frequency
- Alert on unusual session patterns
- Measure session resolution performance

### Performance Optimization
- Implement Redis connection pooling
- Cache JWKS keys with appropriate TTL
- Optimize session data serialization
- Use efficient cookie parsing algorithms

## Security Considerations

### Token Security
- Short-lived access tokens minimize exposure
- Refresh token rotation prevents replay attacks
- Secure random generation for session IDs
- Proper token revocation on logout

### Cookie Security
- HttpOnly prevents JavaScript access
- Secure flag ensures HTTPS-only transmission
- SameSite prevents CSRF attacks
- Proper expiration handling

### Session Protection
- Redis session encryption at rest
- Secure session ID generation
- Session fixation prevention
- Concurrent session limits

## Related Features
- [User Signin](./user-signin.md) - Session creation during authentication
- [User Signup](./user-signup.md) - Initial session establishment
- [JWT Validation](../security/jwt-validation.md) - Token security implementation
- [Rate Limiting](../security/rate-limiting.md) - Session-based rate limiting