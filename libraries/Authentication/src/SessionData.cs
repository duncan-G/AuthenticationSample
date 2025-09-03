namespace AuthSample.Authentication;

public sealed record SessionData(
    string AccessToken, string IdToken, string RefreshToken, DateTime Expiry, string Sub);
