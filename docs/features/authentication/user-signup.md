# User Signup Flow

## Overview

The user signup feature provides multiple registration options including password-based and passwordless authentication. Users can sign up using email/password, passwordless email verification, or social authentication providers (Google, Apple). The system supports a multi-step verification process with email confirmation and rate limiting for security.

## Implementation

### Frontend Components

**Main Signup Interface** (`clients/auth-sample/src/components/auth/main-sign-up.tsx`)
- Provides signup method selection (Google, Apple, Password, Passwordless)
- Handles initial user interaction and method routing
- Includes terms of service and privacy policy acceptance

**Signup Flow Management** (`clients/auth-sample/src/hooks/useAuth.ts`)
- Manages signup state transitions and workflow orchestration
- Handles different signup methods (password, passwordless, social)
- Integrates with gRPC backend services for user registration

**Email Collection** (`clients/auth-sample/src/components/auth/signup-email.tsx`)
- Collects and validates email addresses
- Checks email availability for password-based signup
- Initiates verification process for passwordless signup

**Password Setup** (`clients/auth-sample/src/components/auth/signup-password.tsx`)
- Collects password and confirmation for password-based signup
- Validates password strength and confirmation matching
- Initiates signup with password credentials

### Backend Services

**SignUp gRPC Service** (`microservices/Auth/src/Auth.Grpc/Services/SignUpService.cs`)
- `InitiateSignUpAsync`: Handles signup initiation with email availability checking
- `VerifyAndSignInAsync`: Completes signup after email verification
- Implements rate limiting and user eligibility checks

**Identity Service** (`microservices/Auth/src/Auth.Core/Identity/IdentityService.cs`)
- `InitiateSignUpAsync`: Orchestrates signup process based on method
- `InitiatePasswordSignUpAsync`: Handles password-based signup flow
- `InitiatePasswordlessSignUpAsync`: Handles passwordless signup flow

**Protocol Buffer Definition** (`microservices/Auth/src/Auth.Grpc/Protos/sign-up.proto`)
```protobuf
service SignUpService {
  rpc InitiateSignUpAsync (InitiateSignUpRequest) returns (InitiateSignUpResponse);
  rpc VerifyAndSignInAsync (VerifyAndSignInRequest) returns (VerifyAndSignInResponse);
}

enum SignUpStep {
  PASSWORD_REQUIRED = 1;
  VERIFICATION_REQUIRED = 2;
  SIGN_IN_REQUIRED = 3;
  REDIRECT_REQUIRED = 4;
}
```

## Configuration

### Frontend Configuration
- Social authentication providers configured in OIDC settings
- gRPC-Web client configuration for backend communication
- Form validation rules and password requirements

### Backend Configuration
- AWS Cognito integration for user pool management
- Rate limiting configuration (15 attempts per hour per email)
- Email delivery settings for verification codes

## Usage

### Password-Based Signup Flow
1. User selects "Sign up with Password"
2. System collects email address and checks availability
3. User enters password and confirmation
4. System sends verification email
5. User enters verification code
6. Account is created and user is signed in

### Passwordless Signup Flow
1. User selects "Sign up Passwordless"
2. System collects email address
3. System immediately sends verification email
4. User enters verification code
5. Account is created and user is signed in

### Social Authentication Signup
1. User selects Google or Apple signup
2. System redirects to OAuth provider
3. User completes OAuth flow
4. Account is created automatically
5. User is redirected back to application

## Testing

### Unit Tests
- Email validation and availability checking
- Password strength validation
- Signup flow state transitions
- Error handling for various failure scenarios

### Integration Tests
- End-to-end signup flows for all methods
- Email delivery and verification code validation
- Rate limiting enforcement
- Social authentication integration

## Troubleshooting

### Common Issues

**Email Not Received**
- Check spam/junk folders
- Verify email address is correct
- Use resend functionality if available
- Check rate limiting status

**Password Requirements**
- Minimum 8 characters required
- Must include uppercase, lowercase, numbers
- Special characters recommended
- Password confirmation must match

**Social Authentication Failures**
- Verify OAuth provider configuration
- Check redirect URLs are correctly configured
- Ensure provider accounts are not already linked

### Error Messages
- `DuplicateEmailException`: Email already registered
- `VerificationCodeDeliveryFailedException`: Email delivery failed
- `RateLimitExceededException`: Too many signup attempts

## Related Features
- [User Signin](./user-signin.md) - Authentication after signup
- [Verification Codes](./verification-codes.md) - Email verification system
- [Session Management](./session-management.md) - Post-signup session handling
- [Social Authentication](./social-authentication.md) - OAuth provider integration