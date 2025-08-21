using AuthSample.Auth.Grpc.Protos;
using AuthSample.Auth.Grpc.Validators.SignUp;
using FluentValidation;
using Xunit;

namespace AuthSample.Auth.UnitTests.Validators.SignUp;

public class InitiateSignUpRequestValidatorTests
{
    private readonly InitiateSignUpRequestValidator _validator;

    public InitiateSignUpRequestValidatorTests()
    {
        _validator = new InitiateSignUpRequestValidator();
    }

    [Fact]
    public void Should_Pass_When_Valid_Email_And_No_Password()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Should_Pass_When_Valid_Email_And_Valid_Password()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = "ValidPass123"
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
        var request = new InitiateSignUpRequest
        {
            EmailAddress = email
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
        var request = new InitiateSignUpRequest
        {
            EmailAddress = email
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
    public void Should_Pass_When_Email_Is_Valid(string email)
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = email
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Should_Pass_When_Password_Is_Empty_Or_Whitespace(string password)
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = password
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Theory]
    [InlineData("1234567")] // Too short
    [InlineData("abcdefgh")] // No numbers
    [InlineData("12345678")] // No letters
    [InlineData("ABCDEFGH")] // No numbers, only uppercase
    public void Should_Fail_When_Password_Is_Invalid(string password)
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = password
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var passwordError = result.Errors.FirstOrDefault(e => e.PropertyName == "Password");
        Assert.NotNull(passwordError);
    }

    [Theory]
    [InlineData("ValidPass123")]
    [InlineData("MySecure1")]
    [InlineData("password123")]
    [InlineData("PASSWORD123")]
    [InlineData("Pass1word")]
    [InlineData("123Password")]
    public void Should_Pass_When_Password_Is_Valid(string password)
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = password
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Should_Fail_When_Password_Too_Short()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = "Short1"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var passwordError = result.Errors.FirstOrDefault(e => e.PropertyName == "Password");
        Assert.NotNull(passwordError);
        Assert.Equal("Password must be at least 8 characters when provided.", passwordError.ErrorMessage);
    }

    [Fact]
    public void Should_Fail_When_Password_No_Letters()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = "12345678"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var passwordError = result.Errors.FirstOrDefault(e => e.PropertyName == "Password");
        Assert.NotNull(passwordError);
        Assert.Equal("Password must contain at least one letter when provided.", passwordError.ErrorMessage);
    }

    [Fact]
    public void Should_Fail_When_Password_No_Numbers()
    {
        // Arrange
        var request = new InitiateSignUpRequest
        {
            EmailAddress = "test@example.com",
            Password = "abcdefgh"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var passwordError = result.Errors.FirstOrDefault(e => e.PropertyName == "Password");
        Assert.NotNull(passwordError);
        Assert.Equal("Password must contain at least one number when provided.", passwordError.ErrorMessage);
    }
}
