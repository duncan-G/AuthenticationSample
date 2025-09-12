using System.Net;
using AuthSample.Auth.Core.Identity;
using AuthSample.Auth.Grpc.Protos;
using Microsoft.Extensions.Logging;
using Grpc.Core;
using Moq;
using Xunit.Abstractions;

namespace AuthSample.Auth.IntegrationTests;

/// <summary>
/// Simple integration tests for the ResendVerificationCode functionality
/// Tests the core service logic without complex infrastructure dependencies
/// </summary>
public class ResendVerificationCodeSimpleIntegrationTests : IClassFixture<TestAuthWebApplicationFactory>
{
    private readonly ITestOutputHelper _output;
    private readonly Mock<IIdentityService> _mockIdentityService;
    private readonly Mock<ISignUpEligibilityGuard> _mockEligibilityGuard;
    private readonly Mock<ILogger<AuthSample.Auth.Grpc.Services.SignUpService>> _mockLogger;
    private readonly SignUpService.SignUpServiceClient _client;

    public ResendVerificationCodeSimpleIntegrationTests(
        ITestOutputHelper output,
        TestAuthWebApplicationFactory factory)
    {
        _output = output;
        _mockIdentityService = factory.IdentityServiceMock;
        _mockEligibilityGuard = factory.EligibilityGuardMock;
        _mockLogger = factory.LoggerMock;

        // Reset shared mocks to avoid cross-test invocation leakage
        _mockIdentityService.Reset();
        _mockEligibilityGuard.Reset();
        _mockLogger.Reset();

        _mockEligibilityGuard
            .Setup(x => x.EnforceMaxConfirmedUsersAsync(CancellationToken.None))
            .Returns(Task.CompletedTask);

        var channel = factory.CreateGrpcChannel();
        _client = new SignUpService.SignUpServiceClient(channel);
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_WithValidRequest_ShouldCallIdentityService()
    {
        // Arrange
        var email = "test@example.com";
        var request = new ResendVerificationCodeRequest { EmailAddress = email };
        // Grpc client is backed by test server

        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        // Act
        var response = await _client.ResendVerificationCodeAsyncAsync(request).ConfigureAwait(false);

        // Assert
        Assert.NotNull(response);
        _mockIdentityService.Verify(
            x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()),
            Times.Once);

        _output.WriteLine($"Successfully processed resend for email: {email}");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_WithIdentityServiceFailure_ShouldPropagateException()
    {
        // Arrange
        var email = "failure@example.com";
        var request = new ResendVerificationCodeRequest { EmailAddress = email };
        // Grpc client is backed by test server

        var expectedException = new InvalidOperationException("Identity service error");
        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(expectedException);

        // Act & Assert
        var actualException = await Assert.ThrowsAsync<RpcException>(
            () => _client.ResendVerificationCodeAsyncAsync(request).ResponseAsync);

        Assert.Contains("Identity service error", actualException.Status.Detail);
        _output.WriteLine($"Correctly propagated exception: {actualException.Message}");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_ShouldLogRequestAndResponse()
    {
        // Arrange
        var email = "logging@example.com";
        var request = new ResendVerificationCodeRequest { EmailAddress = email };
        // Grpc client is backed by test server

        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        // Act
        await _client.ResendVerificationCodeAsyncAsync(request).ConfigureAwait(false);

        // Assert - Verify logging occurred
        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("Resending verification code")),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);

        _mockLogger.Verify(
            x => x.Log(
                LogLevel.Information,
                It.IsAny<EventId>(),
                It.Is<It.IsAnyType>((v, t) => v.ToString()!.Contains("Successfully processed resend verification code request")),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.Once);

        _output.WriteLine("Logging verification completed successfully");
    }

    [Fact]
    public async Task CompleteSignUpWorkflow_WithResendOperation_ShouldExecuteAllSteps()
    {
        // Arrange
        var email = "workflow@example.com";
        var password = "TestPassword123!";
        // Grpc client is backed by test server

        // Setup mocks for complete workflow
        _mockIdentityService
            .Setup(x => x.InitiateSignUpAsync(
                It.IsAny<Core.Identity.InitiateSignUpRequest>(),
                It.IsAny<Func<Task>>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(Core.Identity.SignUpStep.VerificationRequired);

        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        _mockIdentityService
            .Setup(x => x.VerifySignUpAndSignInAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ClientSession(
                Guid.NewGuid().ToString(),
                DateTime.UtcNow.AddHours(1),
                Guid.NewGuid().ToString(),
                DateTime.UtcNow.AddDays(30)));

        // Act - Complete workflow with resend
        // 1. Initiate signup
        var initiateRequest = new Grpc.Protos.InitiateSignUpRequest
        {
            EmailAddress = email,
            RequirePassword = true,
            Password = password
        };
        var initiateResponse = await _client.InitiateSignUpAsyncAsync(initiateRequest).ConfigureAwait(false);
        Assert.Equal(Grpc.Protos.SignUpStep.VerificationRequired, initiateResponse.NextStep);

        // 2. Resend verification code
        var resendRequest = new ResendVerificationCodeRequest { EmailAddress = email };
        await _client.ResendVerificationCodeAsyncAsync(resendRequest).ConfigureAwait(false);

        // 3. Verify and sign in
        var verifyRequest = new VerifyAndSignInRequest
        {
            EmailAddress = email,
            VerificationCode = "123456"
        };
        var verifyResponse = await _client.VerifyAndSignInAsyncAsync(verifyRequest).ConfigureAwait(false);

        // Assert
        Assert.Equal(Grpc.Protos.SignUpStep.RedirectRequired, verifyResponse.NextStep);

        // Verify all service calls were made
        _mockIdentityService.Verify(
            x => x.InitiateSignUpAsync(
                It.IsAny<Core.Identity.InitiateSignUpRequest>(),
                It.IsAny<Func<Task>>(),
                It.IsAny<CancellationToken>()),
            Times.Once);
        _mockIdentityService.Verify(
            x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()),
            Times.Once);
        _mockIdentityService.Verify(
            x => x.VerifySignUpAndSignInAsync(It.IsAny<string>(), It.IsAny<string>(), It.IsAny<CancellationToken>()),
            Times.Once);

        _output.WriteLine("Complete workflow with resend operation executed successfully");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_WithEligibilityGuardFailure_ShouldPropagateException()
    {
        // Arrange
        var email = "eligibility-failure@example.com";
        var request = new ResendVerificationCodeRequest { EmailAddress = email };

        var expectedException = new InvalidOperationException("Max users exceeded");
        _mockEligibilityGuard
            .Setup(x => x.EnforceMaxConfirmedUsersAsync(CancellationToken.None))
            .ThrowsAsync(expectedException);

        // Grpc client is backed by test server

        // Act & Assert
        var actualException = await Assert.ThrowsAsync<RpcException>(
            () => _client.ResendVerificationCodeAsyncAsync(request).ResponseAsync);

        Assert.Contains("Max users exceeded", actualException.Status.Detail);
        _output.WriteLine($"Correctly propagated eligibility guard exception: {actualException.Message}");
    }

    [Theory]
    [InlineData("test@example.com")]
    [InlineData("user.name+tag@domain.co.uk")]
    [InlineData("simple@test.org")]
    public async Task ResendVerificationCodeAsync_WithValidEmails_ShouldSucceed(string email)
    {
        // Arrange
        var request = new ResendVerificationCodeRequest { EmailAddress = email };
        // Grpc client is backed by test server

        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        // Act
        var response = await _client.ResendVerificationCodeAsyncAsync(request).ConfigureAwait(false);

        // Assert
        Assert.NotNull(response);
        _mockIdentityService.Verify(
            x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()),
            Times.Once);

        _output.WriteLine($"Successfully processed resend for email: {email}");
    }

    [Fact]
    public async Task ResendVerificationCodeAsync_ServiceIntegration_ShouldCallAllDependencies()
    {
        // Arrange
        var email = "integration@example.com";
        var request = new ResendVerificationCodeRequest { EmailAddress = email };
        _mockIdentityService
            .Setup(x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        // Act
        await _client.ResendVerificationCodeAsyncAsync(request).ConfigureAwait(false);

        // Assert - Verify all dependencies were called
        _mockEligibilityGuard.Verify(x => x.EnforceMaxConfirmedUsersAsync(CancellationToken.None), Times.Once);
        _mockIdentityService.Verify(
            x => x.ResendVerificationCodeAsync(It.IsAny<string>(), It.IsAny<IPAddress>(), It.IsAny<CancellationToken>()),
            Times.Once);

        // Verify logging
        _mockLogger.Verify(
            x => x.Log(
                It.IsAny<LogLevel>(),
                It.IsAny<EventId>(),
                It.IsAny<It.IsAnyType>(),
                It.IsAny<Exception>(),
                It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
            Times.AtLeast(2)); // Should have at least start and end log messages

        _output.WriteLine("Service integration test completed successfully");
    }

    // All calls go through the gRPC client bound to the in-memory test server
}
