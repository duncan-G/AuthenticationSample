namespace AuthSample.Auth.Core.Identity;

public sealed record RefreshTokenRecord(
    string RtId,
    string UserSub,
    string UserEmail,
    string RefreshToken,
    DateTime IssuedAtUtc,
    DateTime ExpiresAtUtc);


