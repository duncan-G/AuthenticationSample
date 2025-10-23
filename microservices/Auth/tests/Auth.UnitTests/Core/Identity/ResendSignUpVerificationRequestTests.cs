using System.Net;
using AuthSample.Auth.Core.Identity;

namespace AuthSample.Auth.UnitTests.Core.Identity;

public class ResendSignUpVerificationRequestTests
{
    [Fact]
    public void Should_Create_Request_With_Constructor()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");

        // Act
        var request = new ResendSignUpVerificationRequest(emailAddress, ipAddress);

        // Assert
        Assert.Equal(emailAddress, request.EmailAddress);
        Assert.Equal(ipAddress, request.IpAddress);
    }

    [Fact]
    public void Should_Have_Immutable_Properties()
    {
        // Arrange
        var emailAddress = "test@example.com";
        var ipAddress = IPAddress.Parse("192.168.1.1");

        // Act
        var request = new ResendSignUpVerificationRequest(emailAddress, ipAddress);

        // Assert
        Assert.Equal(emailAddress, request.EmailAddress);
        Assert.Equal(ipAddress, request.IpAddress);

        // Properties should be read-only (get-only)
        var emailProperty = typeof(ResendSignUpVerificationRequest).GetProperty(nameof(ResendSignUpVerificationRequest.EmailAddress));
        var ipProperty = typeof(ResendSignUpVerificationRequest).GetProperty(nameof(ResendSignUpVerificationRequest.IpAddress));

        Assert.False(emailProperty?.CanWrite);
        Assert.False(ipProperty?.CanWrite);
    }
}
