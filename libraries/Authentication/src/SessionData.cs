namespace AuthSample.Authentication;

public sealed record SessionData(
    DateTime IssuedAt,
    string AccessToken,
    string IdToken,
    DateTime AccessTokenExpiry,
    string RefreshToken,
    DateTime RefreshTokenExpiry,
    string Sub);
