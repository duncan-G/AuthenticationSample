# User Signin Flow

## Overview

The user signin feature provides multiple authentication methods including email/password, passwordless authentication, social login (Google, Apple), and passkey authentication. The system supports secure session management with JWT tokens and automatic session refresh capabilities.

## Implementation

### Frontend Components

**Main Signin Interface** (`clients/auth-sample/src/components/auth/main-sign-in.tsx`)
- Provides signin method selection (Google, Apple, Email)
- Handles initial authentication method routing
- Includes terms of service acceptance

**Authentication Method Components**
- `password-sign-in.tsx`: Email/password authentication form
- `passwordless-sign-in.tsx`: Email-only authentication with verification
- `passkey-sign-in.tsx`: WebAuthn/passkey authentication
- `google-sign-in-button.tsx`: Google OAuth integration
- `apple-sign-in-button.tsx`: Apple OAuth integration

**Authentication Hook** (`clients/auth-sample/src/hooks/useAuth.ts`)
- Manages signin state and flow transitions
- Handles different authentication methods
- Integrates with OIDC client for OAuth flows
- Manages error states and loading indicators

### Backend Services

**Authentication Middleware** (`clients/auth-sample/src/middleware.ts`)
- Validates JWT tokens on protected routes
- Handles automatic token refresh
- Manages authentication redirects
- Implements session resolution

**Session Resolution** (`microservices/Auth/src/Auth.Core/Identity/IdentityService.cs`)
- `ResolveSessionAsync`: Validates and refreshes user sessions
- Handles access token validation and refresh token rotation
- Manages session caching with Redis
- Implements secure cookie-based session storage

**Token Validation** (`libraries/Authentication/src/TokenValidationParametersHelper.cs`)
- Configures JWT validation parameters
- Fetches JWKS from OIDC discovery endpoint
- Handles token signature validation
- Manages issuer and audience validation

## Configuration

### OIDC Configuration
```typescript
// Frontend OIDC client configuration
{
  authority: process.env.NEXT_PUBLIC_OIDC_AUTHORITY,
  client_id: process.env.NEXT_PUBLIC_OIDC_CLIENT_ID,
  redirect_uri: `${window.location.origin}/auth/callback`,
  response_type: 'code',
  scope: 'openid profile email'
}
```

### JWT Validation Settings
```csharp
// Backend token validation
{
  ValidateIssuerSigningKey: true,
  ValidateIssuer: true,
  ValidateAudience: false,
  ValidateLifetime: true,
  ClockSkew: TimeSpan.FromSeconds(60)
}
```

### Session Management
- Access tokens cached in Redis with expiration
- Refresh tokens stored securely with rotation
- HttpOnly, Secure, SameSite cookies for session IDs
- Automatic token refresh on expiration

## Usage

### Email/Password Signin
1. User enters email and password
2. System validates credentials via OIDC
3. JWT tokens are issued and stored securely
4. User is redirected to protected application

### Passwordless Signin
1. User enters email address
2. System sends verification code via email
3. User enters verification code
4. JWT tokens are issued upon successful verification
5. User is authenticated and redirected

### Social Authentication
1. User selects Google or Apple signin
2. System redirects to OAuth provider
3. User completes OAuth flow
4. Provider returns authorization code
5. System exchanges code for tokens
6. User is authenticated and redirected

### Passkey Authentication
1. User initiates passkey signin
2. System challenges user's authenticator
3. User provides biometric or PIN verification
4. WebAuthn assertion is validated
5. User is authenticated without password

## Testing

### Authentication Flow Tests
```typescript
// Integration test example
describe('Authentication Flow', () => {
  it('should authenticate user with valid credentials', async () => {
    await signIn('user@example.com', 'password123');
    expect(await isAuthenticated()).toBe(true);
  });
});
```

### Session Management Tests
- Token validation and refresh scenarios
- Session expiration handling
- Cookie security and HttpOnly enforcement
- Cross-site request forgery protection

### Error Handling Tests
- Invalid credentials handling
- Network failure recovery
- Token expiration scenarios
- Rate limiting enforcement

## Troubleshooting

### Common Issues

**Authentication Failures**
- Verify credentials are correct
- Check account is not locked or suspended
- Ensure email is verified for passwordless
- Validate OAuth provider configuration

**Session Issues**
- Clear browser cookies and retry
- Check token expiration times
- Verify Redis connectivity for session storage
- Validate JWT signing keys are current

**Social Authentication Problems**
- Verify OAuth client configuration
- Check redirect URI whitelist
- Ensure provider accounts are properly linked
- Validate scope permissions

### Error Codes
- `InvalidCredentialsException`: Wrong email/password
- `AccountLockedException`: Account temporarily locked
- `TokenExpiredException`: Session expired, refresh required
- `OAuthProviderException`: Social authentication failed

### Debugging Steps
1. Check browser network tab for failed requests
2. Verify JWT token structure and claims
3. Check server logs for authentication errors
4. Validate OIDC discovery endpoint accessibility
5. Test with different browsers/incognito mode

## Related Features
- [User Signup](./user-signup.md) - Account creation process
- [Verification Codes](./verification-codes.md) - Email verification system
- [Session Management](./session-management.md) - Token and session handling
- [Social Authentication](./social-authentication.md) - OAuth provider integration