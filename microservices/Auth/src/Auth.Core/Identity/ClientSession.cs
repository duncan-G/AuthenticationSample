namespace AuthSample.Auth.Core.Identity;

public record ClientSession(
    string AccessTokenId,
    DateTime AccessTokenExpiry,
    string RefreshTokenId,
    DateTime RefreshTokenExpiry);
