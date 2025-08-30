using System.Net;

namespace AuthSample.Auth.Core;

public sealed class InitiateSignUpRequest
{
    public InitiateSignUpRequest()
    {
    }

    public InitiateSignUpRequest(string emailAddress, IPAddress ipAddress, bool requirePassword, string? password = null)
    {
        EmailAddress = emailAddress;
        IpAddress = ipAddress;
        Password = password;
        RequirePassword = requirePassword;
    }

    public required string EmailAddress { get; set; }
    public required IPAddress IpAddress { get; set; }

    public bool RequirePassword { get; set; }
    public string? Password { get; set; }
}
