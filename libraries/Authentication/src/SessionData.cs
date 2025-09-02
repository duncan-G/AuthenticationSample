namespace AuthSample.Authentication;

public sealed record SessionData(
    string AccessToken, string IdToken, DateTime Expiry, string Sub, string Email);
