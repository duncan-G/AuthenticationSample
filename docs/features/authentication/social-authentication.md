# Social Authentication Integration

## Overview

The social authentication system provides seamless integration with major OAuth providers including Google and Apple. It implements industry-standard OAuth 2.0 and OpenID Connect flows with secure token handling, user profile integration, and comprehensive error handling.

## Implementation

### Frontend Social Authentication

**Google Sign-In Button** (`clients/auth-sample/src/components/auth/google-sign-in-button.tsx`)
- Google-compliant button styling and branding
- Multiple themes (light, dark, neutral) and text options
- Accessibility features and keyboard navigation
- Proper Google branding guidelines compliance

**Apple Sign-In Button** (`clients/auth-sample/src/components/auth/apple-sign-in-button.tsx`)
- Apple Human Interface Guidelines compliance
- Dark and light theme variants
- Proper Apple branding and iconography
- Touch-friendly sizing and interaction

**Social Authentication Flow** (`clients/auth-sample/src/hooks/useAuth.ts`)
```typescript
// Google OAuth flow
const handleGoogleSignIn = withLoading(setIsLoading, async () => {
  await oidc.signinRedirect(); // Redirects to Google OAuth
});

// Apple OAuth flow  
const handleAppleSignIn = withLoading(setIsLoading, async () => {
  await oidc.signinRedirect(); // Redirects to Apple OAuth
});
```

### OIDC Client Configuration

**OpenID Connect Setup**
- React OIDC Context for state management
- Automatic token refresh and validation
- Secure redirect URI handling
- Scope management for profile access

**Configuration Example**
```typescript
{
  authority: process.env.NEXT_PUBLIC_OIDC_AUTHORITY,
  client_id: process.env.NEXT_PUBLIC_OIDC_CLIENT_ID,
  redirect_uri: `${window.location.origin}/auth/callback`,
  response_type: 'code',
  scope: 'openid profile email',
  automaticSilentRenew: true,
  loadUserInfo: true
}
```

### Backend OAuth Integration

**OAuth Provider Configuration**
- AWS Cognito User Pool with social identity providers
- Google OAuth 2.0 client configuration
- Apple Sign In service configuration
- Secure client secret management

**Token Exchange Process**
1. Frontend receives authorization code from provider
2. Backend exchanges code for access/ID tokens
3. User profile information is extracted
4. Local user account is created or linked
5. Application session is established

## Configuration

### Google OAuth Setup

**Google Cloud Console Configuration**
1. Create OAuth 2.0 client credentials
2. Configure authorized redirect URIs
3. Set up consent screen and scopes
4. Enable Google+ API for profile access

**Required Scopes**
- `openid`: OpenID Connect authentication
- `profile`: Basic profile information
- `email`: Email address access

### Apple Sign In Setup

**Apple Developer Configuration**
1. Create Sign In with Apple service ID
2. Configure return URLs and domains
3. Generate and configure private key
4. Set up team ID and key ID

**Apple-Specific Requirements**
- Domain verification for return URLs
- Email relay service configuration
- Private email handling for privacy

### AWS Cognito Integration

**Identity Provider Configuration**
```json
{
  "Google": {
    "client_id": "google-oauth-client-id",
    "client_secret": "google-oauth-client-secret",
    "authorize_scopes": "openid profile email"
  },
  "Apple": {
    "client_id": "apple-service-id",
    "team_id": "apple-team-id",
    "key_id": "apple-key-id",
    "private_key": "apple-private-key"
  }
}
```

## Usage

### Google Authentication Flow
1. User clicks "Continue with Google" button
2. System redirects to Google OAuth consent screen
3. User grants permissions for profile and email access
4. Google redirects back with authorization code
5. Backend exchanges code for tokens and creates session
6. User is authenticated and redirected to application

### Apple Authentication Flow
1. User clicks "Continue with Apple" button
2. System redirects to Apple ID authentication
3. User authenticates with Apple ID credentials
4. Apple redirects back with authorization code
5. Backend validates and exchanges tokens
6. User session is created with Apple profile data

### Profile Data Handling
- Email addresses are verified by OAuth providers
- Profile pictures and names are imported when available
- Privacy settings respect user preferences
- Account linking handles existing email addresses

## Testing

### OAuth Flow Testing
```typescript
// Mock OAuth provider responses
describe('Social Authentication', () => {
  it('should handle Google OAuth flow', async () => {
    mockGoogleOAuth({
      code: 'auth-code-123',
      profile: { email: 'user@gmail.com', name: 'Test User' }
    });
    
    await handleGoogleSignIn();
    expect(isAuthenticated()).toBe(true);
  });
});
```

### Integration Testing
- End-to-end OAuth flows with real providers
- Error handling for denied permissions
- Account linking with existing users
- Token refresh and validation

### Security Testing
- CSRF protection in OAuth flows
- State parameter validation
- Redirect URI validation
- Token signature verification

## Troubleshooting

### Common Issues

**OAuth Configuration Problems**
- Verify client IDs and secrets are correct
- Check redirect URIs match exactly
- Ensure OAuth consent screens are configured
- Validate domain ownership for Apple

**Authentication Failures**
- Check OAuth provider status pages
- Verify network connectivity to provider APIs
- Validate SSL certificate configuration
- Ensure proper scope permissions

**Account Linking Issues**
- Handle existing accounts with same email
- Manage multiple OAuth provider accounts
- Resolve profile data conflicts
- Handle email verification requirements

### Error Handling

**OAuth Error Responses**
- `access_denied`: User denied permissions
- `invalid_request`: Malformed OAuth request
- `invalid_client`: Invalid client credentials
- `server_error`: OAuth provider temporary failure

**Application Error Handling**
```typescript
try {
  await oidc.signinRedirect();
} catch (error) {
  if (error.error === 'access_denied') {
    setErrorMessage('Authentication was cancelled');
  } else {
    setErrorMessage('Authentication failed. Please try again.');
  }
}
```

### Debugging Steps
1. Check browser network tab for OAuth redirects
2. Verify OAuth provider configuration
3. Test with OAuth provider debugging tools
4. Validate JWT tokens from providers
5. Check server logs for token exchange errors

## Security Considerations

### OAuth Security Best Practices
- Use PKCE (Proof Key for Code Exchange) when supported
- Validate state parameters to prevent CSRF
- Implement proper redirect URI validation
- Use secure random state generation

### Token Security
- Validate OAuth provider JWT signatures
- Implement proper token expiration handling
- Secure storage of refresh tokens
- Regular rotation of client secrets

### Privacy Considerations
- Respect user privacy preferences
- Handle Apple's private email relay
- Implement proper data retention policies
- Provide clear privacy disclosures

## Related Features
- [User Signin](./user-signin.md) - Primary authentication flows
- [User Signup](./user-signup.md) - Account creation with social providers
- [Session Management](./session-management.md) - Post-authentication session handling
- [JWT Validation](../security/jwt-validation.md) - Token security implementation