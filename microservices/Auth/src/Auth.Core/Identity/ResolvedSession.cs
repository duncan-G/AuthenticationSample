using AuthSample.Authentication;

namespace AuthSample.Auth.Core.Identity;

public sealed record ResolvedSession(
    SessionData? Session,
    string? NewAccessTokenId,
    DateTime? AccessTokenExpiry,
    bool ShouldClearRefreshCookie);


