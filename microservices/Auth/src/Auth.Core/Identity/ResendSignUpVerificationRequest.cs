using System.Net;

namespace AuthSample.Auth.Core.Identity;

public sealed class ResendSignUpVerificationRequest
{
    public ResendSignUpVerificationRequest(string emailAddress, IPAddress ipAddress)
    {
        EmailAddress = emailAddress;
        IpAddress = ipAddress;
    }

    public string EmailAddress { get; }
    public IPAddress IpAddress { get; }
}