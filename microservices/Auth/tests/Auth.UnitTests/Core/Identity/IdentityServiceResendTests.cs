using System.Net;
using AuthSample.Auth.Core.Exceptions;
using AuthSample.Auth.Core.Identity;
using Microsoft.Extensions.Logging;
using Moq;

namespace AuthSample.Auth.UnitTests.Core.Identity;

/// <summary>
/// Focused tests for the ResendVerificationCodeAsync method in IdentityService
/// These tests use a minimal setup to avoid complex dependency mocking
/// </summary>
public class IdentityServiceResendTests
{
    private readonly Mock<IIdentityGateway> _mockIdentityGateway = new();
    private readonly Mock<ILogger<IdentityService>> _mockLogger = new();

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Call_Gateway_With_Correct_Parameters()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(
                It.Is<ResendSignUpVerificationRequest>(r => r.EmailAddress == emailAddress && r.IpAddress == ipAddress),
                cancellationToken))
            .Returns(Task.CompletedTask);

        var identityService = CreateIdentityService();

        // Act
        await identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken);

        // Assert
        _mockIdentityGateway.Verify(
            x => x.ResendSignUpVerificationAsync(
                It.Is<ResendSignUpVerificationRequest>(r => r.EmailAddress == emailAddress && r.IpAddress == ipAddress),
                cancellationToken),
            Times.Once);
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Handle_DeliveryFailed_Exception()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;
        var exception = new VerificationCodeDeliveryFailedException("Email service unavailable");

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .ThrowsAsync(exception);

        var identityService = CreateIdentityService();

        // Act & Assert
        var thrownException = await Assert.ThrowsAsync<VerificationCodeDeliveryFailedException>(
            () => identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken));

        Assert.Equal("Email service unavailable", thrownException.Message);
        Assert.Same(exception, thrownException);

        // Verify logging
        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Error, "Failed to deliver verification code to");
        VerifyLogNotCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Handle_DeliveryTooSoon_Exception()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;
        var exception = new VerificationCodeDeliveryTooSoonException("Please wait before requesting another code");

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .ThrowsAsync(exception);

        var identityService = CreateIdentityService();

        // Act & Assert
        var thrownException = await Assert.ThrowsAsync<VerificationCodeDeliveryTooSoonException>(
            () => identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken));

        Assert.Equal("Please wait before requesting another code", thrownException.Message);

        // Verify logging
        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Warning, "Resend verification code attempted too soon for");
        VerifyLogNotCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Handle_UserNotFound_Exception()
    {
        // Arrange
        var emailAddress = "nonexistent@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;
        var exception = new UserWithEmailNotFoundException();

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .ThrowsAsync(exception);

        var identityService = CreateIdentityService();

        // Act & Assert
        await Assert.ThrowsAsync<UserWithEmailNotFoundException>(
            () => identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken));

        // Verify logging
        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Warning, "Attempted to resend verification code for non-existent user");
        VerifyLogNotCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Handle_Unexpected_Exception()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;
        var exception = new InvalidOperationException("Unexpected error occurred");

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .ThrowsAsync(exception);

        var identityService = CreateIdentityService();

        // Act & Assert
        var thrownException = await Assert.ThrowsAsync<InvalidOperationException>(
            () => identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken));

        Assert.Equal("Unexpected error occurred", thrownException.Message);

        // Verify logging
        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Error, "Unexpected error while resending verification code to");
        VerifyLogNotCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Log_Success_When_Gateway_Succeeds()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationToken = CancellationToken.None;

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .Returns(Task.CompletedTask);

        var identityService = CreateIdentityService();

        // Act
        await identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken);

        // Assert
        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Theory]
    [InlineData("user@gmail.com", "192.168.1.1")]
    [InlineData("test@company.org", "10.0.0.1")]
    [InlineData("admin@localhost", "127.0.0.1")]
    public async Task ResendVerificationCodeAsync_Should_Handle_Various_Email_And_IP_Combinations(string emailAddress, string ipAddressString)
    {
        // Arrange
        var ipAddress = IPAddress.Parse(ipAddressString);
        var cancellationToken = CancellationToken.None;

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .Returns(Task.CompletedTask);

        var identityService = CreateIdentityService();

        // Act
        await identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken);

        // Assert
        _mockIdentityGateway.Verify(
            x => x.ResendSignUpVerificationAsync(
                It.Is<ResendSignUpVerificationRequest>(r => r.EmailAddress == emailAddress && r.IpAddress == ipAddress),
                cancellationToken),
            Times.Once);

        VerifyLogCalled(LogLevel.Information, "Initiating resend verification code request for");
        VerifyLogCalled(LogLevel.Information, "Successfully resent verification code to");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Create_Correct_Request_Object()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("10.0.0.1");
        var cancellationToken = CancellationToken.None;

        ResendSignUpVerificationRequest? capturedRequest = null;
        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .Callback<ResendSignUpVerificationRequest, CancellationToken>((req, _) => capturedRequest = req)
            .Returns(Task.CompletedTask);

        var identityService = CreateIdentityService();

        // Act
        await identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken);

        // Assert
        Assert.NotNull(capturedRequest);
        Assert.Equal(emailAddress, capturedRequest.EmailAddress);
        Assert.Equal(ipAddress, capturedRequest.IpAddress);
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_Should_Respect_Cancellation_Token()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");
        var cancellationTokenSource = new CancellationTokenSource();
        var cancellationToken = cancellationTokenSource.Token;

        _mockIdentityGateway
            .Setup(x => x.ResendSignUpVerificationAsync(It.IsAny<ResendSignUpVerificationRequest>(), cancellationToken))
            .Returns(async () =>
            {
                await Task.Delay(100, cancellationToken).ConfigureAwait(false);
            });

        var identityService = CreateIdentityService();

        // Act & Assert
        cancellationTokenSource.Cancel();
        await Assert.ThrowsAsync<TaskCanceledException>(
            () => identityService.ResendVerificationCodeAsync(emailAddress, ipAddress, cancellationToken));
    }

    private IdentityService CreateIdentityService()
    {
        // Create minimal mocks for dependencies not used by ResendVerificationCodeAsync
        var mockCache = new Mock<StackExchange.Redis.IConnectionMultiplexer>();
        var mockDatabase = new Mock<StackExchange.Redis.IDatabase>();
        var mockAuthOptions = new Mock<Microsoft.Extensions.Options.IOptions<Authentication.AuthOptions>>();
        var mockRefreshTokenStore = new Mock<IRefreshTokenStore>();
        var mockSignUpEligibilityGuard = new Mock<ISignUpEligibilityGuard>();

        mockCache.Setup(x => x.GetDatabase(It.IsAny<int>(), It.IsAny<object>())).Returns(mockDatabase.Object);
        mockAuthOptions.Setup(x => x.Value).Returns(new Authentication.AuthOptions
        {
            Authority = "https://test-authority.com",
            Audience = "test-audience"
        });

        // Create a real TokenValidationParametersHelper since we can't mock it easily
        // but ResendVerificationCodeAsync doesn't use it anyway
        var tokenHelper = new Authentication.TokenValidationParametersHelper(mockAuthOptions.Object);

        return new IdentityService(
            mockCache.Object,
            mockAuthOptions.Object,
            _mockIdentityGateway.Object,
            mockRefreshTokenStore.Object,
            tokenHelper,
            mockSignUpEligibilityGuard.Object,
            _mockLogger.Object);
    }

    private void VerifyLogCalled(LogLevel level, string messageContains)
    {
        _mockLogger.Verify(
            x => x.Log(
                level,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains(messageContains)),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.AtLeastOnce);
    }

    private void VerifyLogNotCalled(LogLevel level, string messageContains)
    {
        _mockLogger.Verify(
            x => x.Log(
                level,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains(messageContains)),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Never);
    }
}
