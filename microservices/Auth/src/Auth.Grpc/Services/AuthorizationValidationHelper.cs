using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using AuthSample.Authentication;
using Grpc.Core;
using Microsoft.IdentityModel.Tokens;
using StackExchange.Redis;

namespace AuthSample.Auth.Grpc.Services;

public static class AuthorizationValidationHelper
{
    public sealed record AuthorizationValidationResult(
        bool IsValid,
        SessionData? Session,
        StatusCode? FailureCode,
        string? FailureMessage);

    public static async Task<AuthorizationValidationResult> ValidateFromCookieHeaderAsync(
        string? cookieHeader,
        IConnectionMultiplexer cache,
        TokenValidationParametersHelper tokenParameterHelper,
        ILogger logger,
        CancellationToken cancellationToken = default)
    {
        var sessionId = ParseCookie(cookieHeader, "AT_SID");

        if (string.IsNullOrEmpty(sessionId))
        {
            logger.LogInformation("No AT_SID cookie found, denying access.");
            return new AuthorizationValidationResult(false, null, StatusCode.Unauthenticated, "Session cookie missing.");
        }

        var redisDb = cache.GetDatabase();

        var sessionJson = await redisDb.StringGetAsync($"sess:{sessionId}").ConfigureAwait(false);
        if (!sessionJson.HasValue)
        {
            logger.LogWarning("Session ID {SessionId} not found in Redis, denying access.", sessionId);
            return new AuthorizationValidationResult(false, null, StatusCode.Unauthenticated, "Session not found.");
        }

        var sessionData = JsonSerializer.Deserialize<SessionData>(sessionJson.ToString());
        if (sessionData == null)
        {
            logger.LogError("Failed to deserialize session data for {SessionId}.", sessionId);
            return new AuthorizationValidationResult(false, null, StatusCode.Internal, "Invalid session data.");
        }

        try
        {
            var validationParameters = await tokenParameterHelper.GetTokenValidationParameters(cancellationToken).ConfigureAwait(false);
            var handler = new JwtSecurityTokenHandler();
            handler.ValidateToken(sessionData.AccessToken, validationParameters, out _);
            logger.LogInformation("Token validated for user {Subject}, allowing access.", sessionData.Sub);
            return new AuthorizationValidationResult(true, sessionData, null, null);
        }
        catch (SecurityTokenExpiredException ex)
        {
            logger.LogWarning(ex, "Token expired for session {SessionId}.", sessionId);
            return new AuthorizationValidationResult(false, null, StatusCode.Unauthenticated, "Token expired.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Token validation failed for session {SessionId}.", sessionId);
            return new AuthorizationValidationResult(false, null, StatusCode.PermissionDenied, "Token validation failed.");
        }
    }

    public static string? ParseCookie(string? cookieHeader, string cookieName)
    {
        if (string.IsNullOrEmpty(cookieHeader))
        {
            return null;
        }

        var cookies = cookieHeader.Split(';');
        foreach (var cookie in cookies)
        {
            var parts = cookie.Trim().Split('=');
            if (parts.Length == 2 && parts[0].Equals(cookieName, StringComparison.OrdinalIgnoreCase))
            {
                return parts[1];
            }
        }

        return null;
    }
}


