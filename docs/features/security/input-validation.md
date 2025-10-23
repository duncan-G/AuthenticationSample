# Input Validation and Parameter Sanitization

## Overview

The authentication system implements comprehensive input validation and parameter sanitization using FluentValidation for request validation and built-in .NET mechanisms for parameter sanitization. The system ensures data integrity, prevents injection attacks, and provides clear validation error messages to clients.

## Implementation

### Architecture

The input validation system consists of several components:

- **ValidationInterceptor**: gRPC interceptor for automatic request validation
- **FluentValidation**: Declarative validation rules for request objects
- **Parameter Sanitization**: Built-in protection against injection attacks
- **Error Mapping**: Structured validation error responses

### Validation Interceptor

The `ValidationInterceptor` automatically validates all gRPC requests:

```csharp
public sealed class ValidationInterceptor(IServiceProvider serviceProvider) : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        // Try to get a validator for the TRequest type
        if (serviceProvider.GetService(typeof(IValidator<TRequest>)) is not IValidator<TRequest> validator)
        {
            return await continuation(request, context).ConfigureAwait(false);
        }

        var result = await validator.ValidateAsync(request).ConfigureAwait(false);
        if (result.IsValid)
        {
            return await continuation(request, context).ConfigureAwait(false);
        }

        // Create structured validation error response
        var errorCodes = result.Errors.Select(e => e.ErrorCode);
        var errorMessages = result.Errors.Select(e => e.ErrorMessage);
        var metadata = new Metadata {
            { "Error-Codes", string.Join(",", errorCodes) },
            { "Messages", string.Join(",", errorMessages) }
        };
        throw new RpcException(new Status(StatusCode.InvalidArgument, "Bad request"), metadata);
    }
}
```

### FluentValidation Rules

#### Email Validation

```csharp
public class InitiateSignUpRequestValidator : AbstractValidator<InitiateSignUpRequest>
{
    public InitiateSignUpRequestValidator()
    {
        RuleFor(x => x.EmailAddress)
            .NotEmpty()
            .WithErrorCode(ErrorCodes.MissingParameter)
            .WithMessage("Email address is required.")
            .EmailAddress()
            .WithErrorCode(ErrorCodes.InvalidParameter)
            .WithMessage("Please enter a valid email address.")
            .MaximumLength(254) // RFC 5321 limit
            .WithErrorCode(ErrorCodes.InvalidLength)
            .WithMessage("Email address is too long.");
    }
}
```

#### Password Validation

```csharp
public class PasswordValidator : AbstractValidator<string>
{
    public PasswordValidator()
    {
        RuleFor(password => password)
            .NotEmpty()
            .WithErrorCode(ErrorCodes.MissingParameter)
            .WithMessage("Password is required.")
            .MinimumLength(8)
            .WithErrorCode(ErrorCodes.InvalidLength)
            .WithMessage("Password must be at least 8 characters long.")
            .MaximumLength(128)
            .WithErrorCode(ErrorCodes.InvalidLength)
            .WithMessage("Password is too long.")
            .Matches(@"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]")
            .WithErrorCode(ErrorCodes.InvalidParameter)
            .WithMessage("Password must contain at least one uppercase letter, one lowercase letter, one number, and one special character.");
    }
}
```

#### Verification Code Validation

```csharp
public class VerifyAndSignInRequestValidator : AbstractValidator<VerifyAndSignInRequest>
{
    public VerifyAndSignInRequestValidator()
    {
        RuleFor(x => x.EmailAddress)
            .NotEmpty()
            .WithErrorCode(ErrorCodes.MissingParameter)
            .EmailAddress()
            .WithErrorCode(ErrorCodes.InvalidParameter);

        RuleFor(x => x.VerificationCode)
            .NotEmpty()
            .WithErrorCode(ErrorCodes.MissingParameter)
            .WithMessage("Verification code is required.")
            .Length(6)
            .WithErrorCode(ErrorCodes.InvalidLength)
            .WithMessage("Verification code must be 6 digits.")
            .Matches(@"^\d{6}$")
            .WithErrorCode(ErrorCodes.InvalidParameter)
            .WithMessage("Verification code must contain only numbers.");
    }
}
```

### Parameter Sanitization

#### Email Normalization

```csharp
public static class EmailSanitizer
{
    public static string Normalize(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
            return string.Empty;

        // Trim whitespace and convert to lowercase
        var normalized = email.Trim().ToLowerInvariant();

        // Additional sanitization for common email providers
        if (IsGmailAddress(normalized))
        {
            normalized = NormalizeGmailAddress(normalized);
        }

        return normalized;
    }

    private static bool IsGmailAddress(string email)
    {
        return email.EndsWith("@gmail.com", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeGmailAddress(string email)
    {
        var parts = email.Split('@');
        if (parts.Length != 2) return email;

        var localPart = parts[0];
        var domain = parts[1];

        // Remove dots from Gmail local part
        localPart = localPart.Replace(".", "");

        // Remove everything after + (Gmail aliases)
        var plusIndex = localPart.IndexOf('+');
        if (plusIndex >= 0)
        {
            localPart = localPart.Substring(0, plusIndex);
        }

        return $"{localPart}@{domain}";
    }
}
```

#### Input Sanitization

```csharp
public static class InputSanitizer
{
    public static string SanitizeString(string input, int maxLength = 1000)
    {
        if (string.IsNullOrEmpty(input))
            return string.Empty;

        // Trim whitespace
        var sanitized = input.Trim();

        // Limit length
        if (sanitized.Length > maxLength)
        {
            sanitized = sanitized.Substring(0, maxLength);
        }

        // Remove control characters except newline and tab
        sanitized = new string(sanitized
            .Where(c => !char.IsControl(c) || c == '\n' || c == '\t')
            .ToArray());

        // HTML encode to prevent XSS
        sanitized = System.Web.HttpUtility.HtmlEncode(sanitized);

        return sanitized;
    }

    public static string SanitizeNumericString(string input)
    {
        if (string.IsNullOrEmpty(input))
            return string.Empty;

        // Keep only digits
        return new string(input.Where(char.IsDigit).ToArray());
    }
}
```

## Configuration

### Validator Registration

```csharp
// In Program.cs or Startup.cs
services.AddValidatorsFromAssemblyContaining<InitiateSignUpRequestValidator>();

// Register validation interceptor
services.AddGrpc(options =>
{
    options.Interceptors.Add<ValidationInterceptor>();
});
```

### Custom Validation Rules

```csharp
public static class CustomValidators
{
    public static IRuleBuilderOptions<T, string> MustBeValidVerificationCode<T>(
        this IRuleBuilder<T, string> ruleBuilder)
    {
        return ruleBuilder
            .Must(code => !string.IsNullOrEmpty(code) && 
                         code.Length == 6 && 
                         code.All(char.IsDigit))
            .WithErrorCode(ErrorCodes.InvalidParameter)
            .WithMessage("Verification code must be 6 digits.");
    }

    public static IRuleBuilderOptions<T, string> MustBeSecurePassword<T>(
        this IRuleBuilder<T, string> ruleBuilder)
    {
        return ruleBuilder
            .Must(password => IsSecurePassword(password))
            .WithErrorCode(ErrorCodes.InvalidParameter)
            .WithMessage("Password does not meet security requirements.");
    }

    private static bool IsSecurePassword(string password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < 8)
            return false;

        var hasUpper = password.Any(char.IsUpper);
        var hasLower = password.Any(char.IsLower);
        var hasDigit = password.Any(char.IsDigit);
        var hasSpecial = password.Any(c => "!@#$%^&*()_+-=[]{}|;:,.<>?".Contains(c));

        return hasUpper && hasLower && hasDigit && hasSpecial;
    }
}
```

## Usage

### Request Validation

```csharp
public class SignUpService : SignUpServiceBase
{
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(
        InitiateSignUpRequest request, 
        ServerCallContext context)
    {
        // Validation happens automatically via ValidationInterceptor
        // If validation fails, RpcException is thrown before this code runs

        // Sanitize input before processing
        var sanitizedEmail = EmailSanitizer.Normalize(request.EmailAddress);
        
        // Process with sanitized input
        var result = await identityService.InitiateSignUpAsync(new Core.Identity.InitiateSignUpRequest
        {
            EmailAddress = sanitizedEmail,
            Password = request.HasPassword ? request.Password : null,
            // ... other properties
        });

        return new InitiateSignUpResponse { NextStep = (SignUpStep)result };
    }
}
```

### Manual Validation

```csharp
public class CustomService
{
    private readonly IValidator<CustomRequest> _validator;

    public CustomService(IValidator<CustomRequest> validator)
    {
        _validator = validator;
    }

    public async Task<CustomResponse> ProcessAsync(CustomRequest request)
    {
        // Manual validation when needed
        var validationResult = await _validator.ValidateAsync(request);
        if (!validationResult.IsValid)
        {
            var errors = validationResult.Errors
                .Select(e => $"{e.PropertyName}: {e.ErrorMessage}")
                .ToArray();
            
            throw new ValidationException($"Validation failed: {string.Join(", ", errors)}");
        }

        // Process validated request
        return await ProcessValidatedRequest(request);
    }
}
```

### Client-Side Validation

```typescript
// Client-side validation before sending requests
export const validateEmail = (email: string): string | null => {
    if (!email) return "Email is required.";
    if (email.length > 254) return "Email is too long.";
    
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) return "Please enter a valid email address.";
    
    return null;
};

export const validateVerificationCode = (code: string): string | null => {
    if (!code) return "Verification code is required.";
    if (code.length !== 6) return "Verification code must be 6 digits.";
    if (!/^\d{6}$/.test(code)) return "Verification code must contain only numbers.";
    
    return null;
};

// Usage in React component
const SignUpForm: React.FC = () => {
    const [email, setEmail] = useState("");
    const [emailError, setEmailError] = useState<string | null>(null);

    const handleEmailChange = (value: string) => {
        setEmail(value);
        setEmailError(validateEmail(value));
    };

    const handleSubmit = async () => {
        const emailValidation = validateEmail(email);
        if (emailValidation) {
            setEmailError(emailValidation);
            return;
        }

        try {
            await signUpService.initiateSignUp({ emailAddress: email });
        } catch (error) {
            // Server-side validation errors are handled by error handling system
            handleApiError(error, setErrorMessage);
        }
    };
};
```

## Testing

### Validator Tests

```csharp
[TestFixture]
public class InitiateSignUpRequestValidatorTests
{
    private InitiateSignUpRequestValidator _validator;

    [SetUp]
    public void SetUp()
    {
        _validator = new InitiateSignUpRequestValidator();
    }

    [Test]
    public async Task Validate_ValidEmail_ReturnsValid()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com"
        };

        // Act
        var result = await _validator.ValidateAsync(request);

        // Assert
        Assert.That(result.IsValid, Is.True);
    }

    [Test]
    public async Task Validate_InvalidEmail_ReturnsInvalid()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "invalid-email"
        };

        // Act
        var result = await _validator.ValidateAsync(request);

        // Assert
        Assert.That(result.IsValid, Is.False);
        Assert.That(result.Errors.First().ErrorCode, Is.EqualTo(ErrorCodes.InvalidParameter));
    }

    [Test]
    public async Task Validate_EmptyEmail_ReturnsInvalid()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = ""
        };

        // Act
        var result = await _validator.ValidateAsync(request);

        // Assert
        Assert.That(result.IsValid, Is.False);
        Assert.That(result.Errors.First().ErrorCode, Is.EqualTo(ErrorCodes.MissingParameter));
    }
}
```

### Integration Tests

```csharp
[Test]
public async Task SignUpService_InvalidRequest_ReturnsValidationError()
{
    // Arrange
    var request = new InitiateSignUpRequest
    {
        EmailAddress = "invalid-email"
    };

    // Act & Assert
    var exception = await Assert.ThrowsAsync<RpcException>(
        () => signUpClient.InitiateSignUpAsync(request)
    );

    Assert.That(exception.StatusCode, Is.EqualTo(StatusCode.InvalidArgument));
    Assert.That(exception.Trailers.GetValue("Error-Codes"), Contains.Substring(ErrorCodes.InvalidParameter));
}
```

### Client-Side Tests

```typescript
describe('Input Validation', () => {
    describe('validateEmail', () => {
        it('should return null for valid email', () => {
            expect(validateEmail('test@example.com')).toBeNull();
        });

        it('should return error for invalid email', () => {
            expect(validateEmail('invalid-email')).toBe('Please enter a valid email address.');
        });

        it('should return error for empty email', () => {
            expect(validateEmail('')).toBe('Email is required.');
        });

        it('should return error for too long email', () => {
            const longEmail = 'a'.repeat(250) + '@example.com';
            expect(validateEmail(longEmail)).toBe('Email is too long.');
        });
    });

    describe('validateVerificationCode', () => {
        it('should return null for valid code', () => {
            expect(validateVerificationCode('123456')).toBeNull();
        });

        it('should return error for invalid length', () => {
            expect(validateVerificationCode('12345')).toBe('Verification code must be 6 digits.');
        });

        it('should return error for non-numeric code', () => {
            expect(validateVerificationCode('12345a')).toBe('Verification code must contain only numbers.');
        });
    });
});
```

## Troubleshooting

### Common Issues

#### Validation Not Triggered
- **Cause**: Validator not registered in DI container
- **Solution**: Ensure `AddValidatorsFromAssemblyContaining<T>()` is called
- **Check**: Verify `ValidationInterceptor` is added to gRPC pipeline

#### Custom Error Codes Not Working
- **Cause**: Error codes not properly configured in validation rules
- **Solution**: Use `.WithErrorCode()` method in FluentValidation rules
- **Example**: `.WithErrorCode(ErrorCodes.InvalidParameter)`

#### Client Not Receiving Validation Errors
- **Cause**: Validation errors not properly formatted in metadata
- **Solution**: Check that `ValidationInterceptor` adds error codes to metadata
- **Debug**: Log gRPC metadata on client side

### Performance Considerations

#### Validation Caching
```csharp
// Cache compiled validation rules for better performance
services.AddSingleton<IValidator<InitiateSignUpRequest>>(provider =>
{
    var validator = new InitiateSignUpRequestValidator();
    // Pre-compile validation rules
    validator.ValidateAsync(new InitiateSignUpRequest()).Wait();
    return validator;
});
```

#### Async Validation
```csharp
// Use async validation for database checks
RuleFor(x => x.EmailAddress)
    .MustAsync(async (email, cancellation) => 
    {
        return !await userRepository.ExistsAsync(email, cancellation);
    })
    .WithErrorCode(ErrorCodes.DuplicateEmail)
    .WithMessage("This email is already in use.");
```

### Security Considerations

#### Input Sanitization
- **Always sanitize**: Sanitize all user input before processing
- **Context-aware**: Use appropriate sanitization for the context (HTML, SQL, etc.)
- **Validation first**: Validate before sanitizing to provide clear error messages

#### Injection Prevention
- **Parameterized queries**: Use parameterized queries for database operations
- **HTML encoding**: Encode output when displaying user input
- **Regular expressions**: Use safe regex patterns to prevent ReDoS attacks

## Related Features

- [Error Handling](error-handling.md) - Validation error processing
- [Rate Limiting](rate-limiting.md) - Preventing validation abuse
- [JWT Validation](jwt-validation.md) - Token parameter validation