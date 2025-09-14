# Error Handling System

## Overview

The authentication system implements a comprehensive error handling system that provides consistent, user-friendly error messages while maintaining security best practices. The system includes structured error codes, friendly message mapping, and proper error propagation from backend services to frontend clients.

## Implementation

### Architecture

The error handling system consists of several layers:

- **Backend Error Handling**: gRPC interceptors and structured error codes
- **Error Code Mapping**: Centralized error code definitions
- **Client-Side Handling**: Friendly message resolution and user feedback
- **Security Considerations**: Information disclosure prevention

### Backend Error Handling

#### Exception Interceptor

The `ExceptionsInterceptor` provides centralized exception handling for all gRPC services:

```csharp
public sealed class ExceptionsInterceptor : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        try
        {
            return await continuation(request, context);
        }
        catch (Exception ex) when (ex is IHasGrpcClientError mappedEx)
        {
            // Domain errors with known error codes
            logger.LogWarning(ex, "Domain error: {Message}", ex.Message);
            throw mappedEx.ToGrpcError().ToRpcException();
        }
        catch (Exception ex) when (ex is not RpcException)
        {
            // Unexpected errors
            logger.LogError(ex, "Unhandled exception");
            
            var message = hostEnvironment.IsEnvironment("Testing")
                ? ex.Message  // Detailed messages in testing
                : "An unexpected error occurred."; // Generic message in production

            var descriptor = new GrpcErrorDescriptor(
                StatusCode.Internal,
                ErrorCodes.Unexpected,
                Message: message);
            throw descriptor.ToRpcException();
        }
    }
}
```

#### Validation Interceptor

The `ValidationInterceptor` handles request validation using FluentValidation:

```csharp
public sealed class ValidationInterceptor : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        if (serviceProvider.GetService(typeof(IValidator<TRequest>)) is not IValidator<TRequest> validator)
        {
            return await continuation(request, context);
        }

        var result = await validator.ValidateAsync(request);
        if (!result.IsValid)
        {
            var errorCodes = result.Errors.Select(e => e.ErrorCode);
            var errorMessages = result.Errors.Select(e => e.ErrorMessage);
            var metadata = new Metadata {
                { "Error-Codes", string.Join(",", errorCodes) },
                { "Messages", string.Join(",", errorMessages) }
            };
            throw new RpcException(new Status(StatusCode.InvalidArgument, "Bad request"), metadata);
        }

        return await continuation(request, context);
    }
}
```

### Error Code System

#### Structured Error Codes

Error codes are organized by category with consistent numbering:

```csharp
// Common/validation errors (1000-1999)
public const string MissingParameter = "1000";
public const string InvalidParameter = "1001";
public const string InvalidLength = "1002";

// Authentication errors (2000-2999)
public const string DuplicateEmail = "2000";
public const string UserNotFound = "2001";
public const string VerificationCodeMismatch = "2002";
public const string VerificationCodeExpired = "2003";
public const string VerificationAttemptsExceeded = "2004";
public const string VerificationCodeDeliveryFailed = "2005";
public const string MaximumUsersReached = "2006";

// System errors (9000-9999)
public const string ResourceExhausted = "9998";
public const string Unexpected = "9999";
```

#### Error Descriptor

The `GrpcErrorDescriptor` provides structured error information:

```csharp
public sealed record GrpcErrorDescriptor(
    StatusCode StatusCode,
    string ErrorCode,
    string? Message = null)
{
    public RpcException ToRpcException()
    {
        var metadata = new Metadata { { "Error-Code", ErrorCode } };
        var status = new Status(StatusCode, Message ?? string.Empty);
        return new RpcException(status, metadata, Message ?? string.Empty);
    }
}
```

### Client-Side Error Handling

#### Friendly Message Mapping

The client maintains a mapping of error codes to user-friendly messages:

```typescript
export const friendlyMessageFor: Record<KnownErrorCode, string> = {
    [ErrorCodes.MissingParameter]: "A required parameter is missing.",
    [ErrorCodes.InvalidParameter]: "An invalid parameter was provided.",
    [ErrorCodes.InvalidLength]: "An invalid length was provided.",
    [ErrorCodes.DuplicateEmail]: "This email is already in use.",
    [ErrorCodes.UserNotFound]: "We couldn't find an account with that email.",
    [ErrorCodes.VerificationCodeMismatch]: "That code doesn't look right. Please try again.",
    [ErrorCodes.VerificationCodeExpired]: "That code has expired. Request a new one to continue.",
    [ErrorCodes.VerificationAttemptsExceeded]: "You've entered too many incorrect codes. Please request a new code later.",
    [ErrorCodes.VerificationCodeDeliveryFailed]: "We couldn't send a verification code. Please try again later.",
    [ErrorCodes.MaximumUsersReached]: "We've reached our user limit. Please try again later.",
    [ErrorCodes.ResourceExhausted]: "You've reached the maximum number of attempts.",
    [ErrorCodes.Unexpected]: "Something went wrong. Please try again in a moment.",
};
```

#### Error Processing Function

The `handleApiError` function provides centralized client-side error handling:

```typescript
export const handleApiError = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>,
    onRateLimitExceeded?: (retryAfterMinutes?: number) => void
) => {
    const { code, serverMessage, retryAfterSeconds } = extractApiError(err);

    console.error("API error (rate-limit aware)", {
        code,
        serverMessage,
        retryAfterSeconds,
        err,
    });

    let friendly = resolveFriendlyMessage(code);

    // Special handling for rate limiting
    if (code === ErrorCodes.ResourceExhausted) {
        const retryAfterMinutes = getRetryAfterMinutes({ retryAfterSeconds, serverMessage });
        const retryAfterLabel = retryAfterMinutes === 1 ? "minute" : "minutes";
        
        if (retryAfterMinutes && retryAfterMinutes > 0) {
            friendly = `${friendly} Please wait ${retryAfterMinutes} ${retryAfterLabel} before trying again.`;
        }
        
        onRateLimitExceeded?.(retryAfterMinutes);
    }

    step?.fail(code ?? "UNKNOWN", friendly);
    setErrorMessage(friendly);
};
```

## Configuration

### Backend Configuration

#### Registering Interceptors

```csharp
// In Program.cs
services.AddGrpc(options =>
{
    options.Interceptors.Add<ExceptionsInterceptor>();
    options.Interceptors.Add<ValidationInterceptor>();
});
```

#### Environment-Specific Behavior

```csharp
// Different error detail levels by environment
var message = hostEnvironment.IsEnvironment("Testing")
    ? ex.Message  // Detailed for testing
    : "An unexpected error occurred."; // Generic for production
```

### Client Configuration

#### Error Code Synchronization

Error codes are shared between backend and frontend through generated TypeScript definitions:

```typescript
// Generated from backend error codes
export const ErrorCodes = {
    MissingParameter: "1000",
    InvalidParameter: "1001",
    DuplicateEmail: "2000",
    UserNotFound: "2001",
    // ... other codes
} as const;

export type KnownErrorCode = typeof ErrorCodes[keyof typeof ErrorCodes];
```

## Usage

### Backend Usage

#### Throwing Domain Errors

```csharp
public class IdentityService : IIdentityService
{
    public async Task<SignUpResult> InitiateSignUpAsync(InitiateSignUpRequest request)
    {
        if (await UserExistsAsync(request.EmailAddress))
        {
            throw new DuplicateEmailException(request.EmailAddress);
        }
        
        // Continue with signup logic...
    }
}

// Domain exception implementing IHasGrpcClientError
public class DuplicateEmailException : Exception, IHasGrpcClientError
{
    public DuplicateEmailException(string email) 
        : base($"User with email {email} already exists") { }

    public GrpcErrorDescriptor ToGrpcError()
    {
        return new GrpcErrorDescriptor(
            StatusCode.AlreadyExists,
            ErrorCodes.DuplicateEmail,
            "This email is already in use."
        );
    }
}
```

#### Rate Limiting Errors

```csharp
// Rate limiting automatically throws structured errors
await context.EnforceFixedByEmailAsync(email, 3600, 5);

// Results in:
// StatusCode: ResourceExhausted
// Error-Code: "9998"
// retry-after-seconds: "3540"
```

### Frontend Usage

#### Component Error Handling

```typescript
const SignUpForm: React.FC = () => {
    const [errorMessage, setErrorMessage] = useState<string>();
    const [isRateLimited, setIsRateLimited] = useState(false);

    const handleSignUp = async (email: string) => {
        try {
            await signUpService.initiateSignUp({ emailAddress: email });
        } catch (error) {
            handleApiError(
                error,
                setErrorMessage,
                undefined,
                (retryAfterMinutes) => {
                    setIsRateLimited(true);
                    // Show rate limit UI with retry time
                }
            );
        }
    };

    return (
        <form onSubmit={handleSignUp}>
            {errorMessage && (
                <div className="error-message">{errorMessage}</div>
            )}
            {isRateLimited && (
                <div className="rate-limit-warning">
                    Please wait before trying again.
                </div>
            )}
            {/* Form fields */}
        </form>
    );
};
```

#### Workflow Integration

```typescript
const signUpWorkflow = useWorkflow("signup", async (email: string) => {
    const step = workflow.startStep("initiate-signup");
    
    try {
        const result = await signUpService.initiateSignUp({ emailAddress: email });
        step.complete();
        return result;
    } catch (error) {
        handleApiError(error, setErrorMessage, step);
        throw error;
    }
});
```

## Testing

### Backend Tests

#### Exception Interceptor Tests

```csharp
[Test]
public async Task ExceptionsInterceptor_DomainException_ReturnsStructuredError()
{
    // Arrange
    var interceptor = new ExceptionsInterceptor(logger, hostEnvironment);
    var context = new TestServerCallContext();
    
    var continuation = new UnaryServerMethod<TestRequest, TestResponse>(
        (req, ctx) => throw new DuplicateEmailException("test@example.com")
    );

    // Act & Assert
    var exception = await Assert.ThrowsAsync<RpcException>(
        () => interceptor.UnaryServerHandler(new TestRequest(), context, continuation)
    );

    Assert.That(exception.StatusCode, Is.EqualTo(StatusCode.AlreadyExists));
    Assert.That(exception.Trailers.GetValue("Error-Code"), Is.EqualTo(ErrorCodes.DuplicateEmail));
}
```

### Frontend Tests

#### Error Handling Tests

```typescript
describe('handleApiError', () => {
    it('should set friendly message for known error code', () => {
        const setErrorMessage = jest.fn();
        const error = {
            metadata: { 'error-code': ErrorCodes.DuplicateEmail }
        };

        handleApiError(error, setErrorMessage);

        expect(setErrorMessage).toHaveBeenCalledWith(
            "This email is already in use."
        );
    });

    it('should handle rate limiting with retry time', () => {
        const setErrorMessage = jest.fn();
        const onRateLimitExceeded = jest.fn();
        const error = {
            metadata: { 
                'error-code': ErrorCodes.ResourceExhausted,
                'retry-after-seconds': '300'
            }
        };

        handleApiError(error, setErrorMessage, undefined, onRateLimitExceeded);

        expect(onRateLimitExceeded).toHaveBeenCalledWith(5); // 5 minutes
        expect(setErrorMessage).toHaveBeenCalledWith(
            expect.stringContaining("Please wait 5 minutes")
        );
    });
});
```

## Troubleshooting

### Common Issues

#### Error Codes Not Propagating
- **Cause**: Missing error code in gRPC metadata
- **Solution**: Ensure `GrpcErrorDescriptor` is used for all domain errors
- **Check**: Verify error code appears in gRPC trailers

#### Friendly Messages Not Displaying
- **Cause**: Error code not found in mapping
- **Solution**: Add missing error codes to `friendlyMessageFor` mapping
- **Fallback**: System shows generic "Something went wrong" message

#### Validation Errors Not Handled
- **Cause**: FluentValidation validator not registered
- **Solution**: Register validators in DI container
- **Check**: Ensure `ValidationInterceptor` is added to gRPC pipeline

### Error Investigation

#### Backend Logging

```csharp
// Structured logging for error investigation
logger.LogWarning(ex, "Domain error: {ErrorCode} - {Message}", 
    errorCode, ex.Message);

logger.LogError(ex, "Unhandled exception in {Service}.{Method}", 
    serviceName, methodName);
```

#### Client-Side Debugging

```typescript
// Comprehensive error logging
console.error("API error (rate-limit aware)", {
    code,
    serverMessage,
    retryAfterSeconds,
    originalError: err,
    timestamp: new Date().toISOString()
});
```

### Security Considerations

#### Information Disclosure
- **Production**: Generic error messages prevent information leakage
- **Testing**: Detailed messages aid in debugging
- **Logging**: Sensitive information is not logged in production

#### Error Code Consistency
- **Centralized**: Error codes defined in single location
- **Versioned**: Error codes remain stable across versions
- **Documented**: All error codes have clear meanings

## Related Features

- [Rate Limiting](rate-limiting.md) - Rate limit error handling
- [JWT Validation](jwt-validation.md) - Authentication error processing
- [Input Validation](input-validation.md) - Request validation errors