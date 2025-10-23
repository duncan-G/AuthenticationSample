using AuthSample.Auth.Grpc.Protos;
using AuthSample.Auth.Grpc.Validators.SignUp;

namespace AuthSample.Auth.UnitTests.Validators.SignUp;

public class VerifyAndSignInRequestValidatorTests
{
    private readonly VerifyAndSignInRequestValidator _validator = new();

    [Fact]
    public void Should_Pass_When_All_Fields_Are_Valid()
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "123456",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Should_Fail_When_Email_Is_Empty_Or_Whitespace(string email)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = email,
            VerificationCode = "123456",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var emailError = result.Errors.FirstOrDefault(e => e.PropertyName == "EmailAddress");
        Assert.NotNull(emailError);
        Assert.Equal("Email address is required.", emailError.ErrorMessage);
    }

    [Theory]
    [InlineData("invalid-email")]
    [InlineData("test@")]
    [InlineData("@example.com")]
    [InlineData("test.example.com")]
    [InlineData("test@@example.com")]
    public void Should_Fail_When_Email_Is_Invalid(string email)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = email,
            VerificationCode = "123456",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var emailError = result.Errors.FirstOrDefault(e => e.PropertyName == "EmailAddress");
        Assert.NotNull(emailError);
        Assert.Equal("Email address is not valid.", emailError.ErrorMessage);
    }

    [Theory]
    [InlineData("test@example.com")]
    [InlineData("user.name@domain.co.uk")]
    [InlineData("user+tag@example.org")]
    [InlineData("123@example.com")]
    [InlineData("user-name@example.com")]
    [InlineData("user_name@example.com")]
    [InlineData("user@subdomain.example.com")]
    [InlineData("user@example-domain.com")]
    public void Should_Pass_When_Email_Is_Valid(string email)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = email,
            VerificationCode = "123456",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Should_Fail_When_VerificationCode_Is_Empty_Or_Whitespace(string verificationCode)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = verificationCode,
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var codeError = result.Errors.FirstOrDefault(e => e.PropertyName == "VerificationCode");
        Assert.NotNull(codeError);
        Assert.Equal("Verification code is required.", codeError.ErrorMessage);
    }

    [Theory]
    [InlineData("12345")] // Too short
    [InlineData("1234567")] // Too long
    public void Should_Fail_When_VerificationCode_Is_Invalid(string verificationCode)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = verificationCode,
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var codeError = result.Errors.FirstOrDefault(e => e.PropertyName == "VerificationCode");
        Assert.NotNull(codeError);
    }

    [Theory]
    [InlineData("123456")]
    [InlineData("000000")]
    [InlineData("999999")]
    [InlineData("123789")]
    public void Should_Pass_When_VerificationCode_Is_Valid(string verificationCode)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = verificationCode,
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Should_Pass_When_Name_Is_Empty_Or_Whitespace(string name)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "123456",
            Name = name
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("A")] // Single character
    [InlineData("AB")] // Two characters
    [InlineData("John")] // Short name
    [InlineData("John Doe")] // Normal name
    [InlineData("Jean-Pierre")] // Name with hyphen
    [InlineData("O'Connor")] // Name with apostrophe
    [InlineData("José María")] // Name with accented characters
    public void Should_Pass_When_Name_Is_Valid(string name)
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "123456",
            Name = name
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    // Name length is no longer validated
    [Fact]
    public void Should_Pass_When_Name_Exceeds_Previous_Maximum_Length()
    {
        // Arrange
        var longName = new string('A', 101); // 101 characters
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "123456",
            Name = longName
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Should_Pass_When_Name_Is_Exactly_Maximum_Length()
    {
        // Arrange
        var maxLengthName = new string('A', 100); // Exactly 100 characters
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "123456",
            Name = maxLengthName
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Should_Have_Correct_Error_Message_For_VerificationCode_Too_Short()
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "12345",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var codeError = result.Errors.FirstOrDefault(e => e.PropertyName == "VerificationCode");
        Assert.NotNull(codeError);
        Assert.Equal("Verification code must be 6 characters.", codeError.ErrorMessage);
    }

    [Fact]
    public void Should_Have_Correct_Error_Message_For_VerificationCode_Too_Long()
    {
        // Arrange
        var request = new VerifyAndSignInRequest
        {
            EmailAddress = "test@example.com",
            VerificationCode = "1234567",
            Name = "John Doe"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var codeError = result.Errors.FirstOrDefault(e => e.PropertyName == "VerificationCode");
        Assert.NotNull(codeError);
        Assert.Equal("Verification code must be 6 characters.", codeError.ErrorMessage);
    }
}
