using System.Net;

namespace AuthSample.Auth.Core;

public sealed class InitiateSignUpRequest
{
    public InitiateSignUpRequest()
    {
    }

    public InitiateSignUpRequest(string emailAddress, IPAddress ipAddress, string? password = null)
    {
        EmailAddress = emailAddress;
        IpAddress = ipAddress;
        Password = password;
    }

    public string EmailAddress { get; set; } = null!;
    public IPAddress IpAddress { get; set; } = null!;
    public string? Password { get; set; }
}
