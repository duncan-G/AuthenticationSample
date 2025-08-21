using AuthSample.Auth.Grpc.Protos;
using AuthSample.Auth.Grpc.Validators.SignUp;
using FluentValidation;
using Xunit;

namespace AuthSample.Auth.UnitTests.Validators.SignUp;

public class IsEmailTakenRequestValidatorTests
{
    private readonly IsEmailTakenRequestValidator _validator;

    public IsEmailTakenRequestValidatorTests()
    {
        _validator = new IsEmailTakenRequestValidator();
    }

    [Fact]
    public void Should_Pass_When_Valid_Email()
    {
        // Arrange
        var request = new IsEmailTakenRequest
        {
            EmailAddress = "test@example.com"
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
        var request = new IsEmailTakenRequest
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
        var request = new IsEmailTakenRequest
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
    [InlineData("user-name@example.com")]
    [InlineData("user_name@example.com")]
    [InlineData("user@subdomain.example.com")]
    [InlineData("user@example-domain.com")]
    public void Should_Pass_When_Email_Is_Valid(string email)
    {
        // Arrange
        var request = new IsEmailTakenRequest
        {
            EmailAddress = email
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.True(result.IsValid);
    }

    [Fact]
    public void Should_Have_Correct_Error_Message_For_Empty_Email()
    {
        // Arrange
        var request = new IsEmailTakenRequest
        {
            EmailAddress = ""
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var emailError = result.Errors.FirstOrDefault(e => e.PropertyName == "EmailAddress");
        Assert.NotNull(emailError);
        Assert.Equal("Email address is required.", emailError.ErrorMessage);
    }

    [Fact]
    public void Should_Have_Correct_Error_Message_For_Invalid_Email()
    {
        // Arrange
        var request = new IsEmailTakenRequest
        {
            EmailAddress = "invalid-email"
        };

        // Act
        var result = _validator.Validate(request);

        // Assert
        Assert.False(result.IsValid);
        var emailError = result.Errors.FirstOrDefault(e => e.PropertyName == "EmailAddress");
        Assert.NotNull(emailError);
        Assert.Equal("Email address is not valid.", emailError.ErrorMessage);
    }
}
