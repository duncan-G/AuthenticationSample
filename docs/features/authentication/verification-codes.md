# Verification Code System

## Overview

The verification code system provides secure email-based verification for user signup and authentication flows. It includes automatic code generation, email delivery, resend functionality with rate limiting, and comprehensive error handling. The system supports both signup verification and passwordless authentication scenarios.

## Implementation

### Frontend Components

**Verification Interface** (`clients/auth-sample/src/components/auth/signup-verification.tsx`)
- 6-digit verification code input with auto-formatting
- Visual feedback for email sent status
- Resend functionality with cooldown timer
- Rate limiting display and error handling
- Auto-focus and accessibility features

**Verification State Management** (`clients/auth-sample/src/hooks/useAuth.ts`)
- `handleSignUpOtpVerification`: Validates verification codes
- `handleResendVerificationCode`: Resends codes with rate limiting
- Error state management for verification failures
- Rate limit tracking and retry-after handling

### Backend Services

**Verification Code Service** (`microservices/Auth/src/Auth.Grpc/Services/SignUpService.cs`)
- `ResendVerificationCodeAsync`: Handles code resend requests
- Rate limiting enforcement (5 attempts per hour per email)
- IP address tracking for security
- Integration with AWS Cognito for code delivery

**Identity Service Implementation** (`microservices/Auth/src/Auth.Core/Identity/IdentityService.cs`)
- `ResendVerificationCodeAsync`: Core resend logic with comprehensive logging
- Exception handling for delivery failures and rate limiting
- Activity tracing for observability
- Integration with identity gateway for code generation

**Protocol Buffer Definition**
```protobuf
message ResendVerificationCodeRequest {
  string email_address = 1;
}

service SignUpService {
  rpc ResendVerificationCodeAsync (ResendVerificationCodeRequest) returns (google.protobuf.Empty);
}
```

### Rate Limiting Implementation

**Email-Based Rate Limiting** (`libraries/Api/src/RateLimiting/`)
- Fixed window rate limiting: 5 attempts per hour per email
- Redis-based distributed rate limiting
- Separate limits for verification codes vs general signup
- Retry-After header support for client-side cooldowns

**Rate Limiting Logic**
```csharp
// Verification code specific rate limiting
await context.EnforceFixedByEmailAsync(
    emailAddress,
    3600, // 1 hour window
    5,    // 5 attempts max
    verificationCodePath,
    cancellationToken
);
```

## Configuration

### Email Delivery Settings
- AWS SES integration for reliable email delivery
- Customizable email templates for verification codes
- Sender domain verification and reputation management
- Bounce and complaint handling

### Rate Limiting Configuration
```csharp
// Rate limiting settings
{
  WindowSizeSeconds: 3600,    // 1 hour window
  MaxAttempts: 5,             // 5 resend attempts
  EmailSpecificLimits: true,  // Per-email limiting
  RetryAfterMinutes: 60       // Cooldown period
}
```

### Code Generation Settings
- 6-digit numeric codes for user-friendliness
- Configurable expiration time (typically 15 minutes)
- Secure random generation with cryptographic entropy
- Single-use validation with automatic cleanup

## Usage

### Signup Verification Flow
1. User completes signup form
2. System generates and sends 6-digit verification code
3. User receives email with verification code
4. User enters code in verification interface
5. System validates code and completes account creation

### Resend Functionality
1. User clicks "Resend code" if email not received
2. System checks rate limiting (5 attempts per hour)
3. New verification code is generated and sent
4. Previous codes are invalidated
5. Client shows 30-second cooldown timer

### Error Handling
- **Rate Limited**: Display retry-after time to user
- **Delivery Failed**: Show error message and suggest alternatives
- **Invalid Code**: Clear input and show validation error
- **Expired Code**: Prompt user to request new code

## Testing

### Unit Tests
```typescript
// Resend functionality test
describe('Resend Verification Code', () => {
  it('should enforce rate limiting', async () => {
    // Attempt 6 resends within rate limit window
    for (let i = 0; i < 6; i++) {
      if (i < 5) {
        await expect(resendCode('user@example.com')).resolves.toBeUndefined();
      } else {
        await expect(resendCode('user@example.com')).rejects.toThrow('Rate limit exceeded');
      }
    }
  });
});
```

### Integration Tests
- End-to-end verification code delivery and validation
- Rate limiting enforcement across multiple requests
- Email delivery failure handling and recovery
- Cross-browser verification code input testing

### Load Testing
- High-volume verification code generation
- Rate limiting performance under load
- Email delivery service capacity testing
- Redis rate limiting store performance

## Troubleshooting

### Common Issues

**Verification Codes Not Received**
- Check spam/junk email folders
- Verify email address is correctly entered
- Confirm sender domain is not blocked
- Check AWS SES delivery status and bounces

**Rate Limiting Issues**
- Display clear retry-after messaging
- Implement exponential backoff for repeated failures
- Monitor rate limiting metrics for abuse patterns
- Consider IP-based rate limiting for additional security

**Code Validation Failures**
- Verify code hasn't expired (15-minute window)
- Check for typos in 6-digit code entry
- Ensure code hasn't been used previously
- Validate email address matches original request

### Error Messages and Codes
- `VerificationCodeDeliveryFailedException`: Email delivery failed
- `VerificationCodeDeliveryTooSoonException`: Rate limit exceeded
- `UserWithEmailNotFoundException`: Invalid email address
- `VerificationCodeExpiredException`: Code expired, request new one

### Monitoring and Alerts
- Track verification code delivery success rates
- Monitor rate limiting trigger frequency
- Alert on unusual verification patterns
- Track email bounce and complaint rates

### Performance Optimization
- Cache verification attempts in Redis
- Implement efficient code generation algorithms
- Optimize email template rendering
- Use connection pooling for database operations

## Related Features
- [User Signup](./user-signup.md) - Primary use case for verification codes
- [User Signin](./user-signin.md) - Passwordless authentication verification
- [Session Management](./session-management.md) - Post-verification session creation
- [Rate Limiting](../security/rate-limiting.md) - Underlying rate limiting system