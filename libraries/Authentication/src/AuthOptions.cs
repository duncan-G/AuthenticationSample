namespace AuthSample.Authentication;

public sealed class AuthOptions
{
    public string Authority { get; set; } = null!;

    public string Audience { get; set; } = null!;
}
