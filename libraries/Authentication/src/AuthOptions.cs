namespace AuthSample.Authentication;

public sealed class AuthOptions
{
    public required string Authority { get; set; }

    public required string Audience { get; set; }
}
