using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using AuthSample.Authentication;
using Microsoft.IdentityModel.Tokens;
using StackExchange.Redis;
using StatusCode = Grpc.Core.StatusCode;

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
        AuthOptions authOptions,
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

            // Parse the JWT token to extract client_id claim
            var handler = new JwtSecurityTokenHandler();
            var token = handler.ReadJwtToken(sessionData.AccessToken);
            var clientIdClaim = token.Claims.FirstOrDefault(c => c.Type == "client_id")?.Value;

            // Validate the token first (issuer, signature, expiration)
            handler.ValidateToken(sessionData.AccessToken, validationParameters, out _);

            // Manual validation: Check client_id claim matches expected backend client ID
            if (string.IsNullOrEmpty(clientIdClaim))
            {
                logger.LogWarning("JWT token missing client_id claim");
                throw new SecurityTokenValidationException("Token missing client_id claim");
            }

            var expectedClientId = authOptions.Audience;

            if (clientIdClaim != expectedClientId)
            {
                logger.LogWarning("JWT token client_id '{ActualClientId}' does not match expected client_id '{ExpectedClientId}'",
                    clientIdClaim, expectedClientId);
                throw new SecurityTokenValidationException($"Invalid client_id claim. Expected: {expectedClientId}, Actual: {clientIdClaim}");
            }

            logger.LogInformation("Token validated for user {Subject}, allowing access.", sessionData.Sub);

            // Record success on the current activity
            var activity = Activity.Current;
            activity?.SetStatus(ActivityStatusCode.Ok);
            activity?.SetTag("auth.validation.success", true);
            activity?.SetTag("auth.validation.user", sessionData.Sub);

            return new AuthorizationValidationResult(true, sessionData, null, null);
        }
        catch (SecurityTokenExpiredException ex)
        {
            logger.LogWarning(ex, "Token expired for session {SessionId}.", sessionId);

            // Record exception and set error status on the current activity
            var activity = Activity.Current;
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, "Token expired");
            activity?.SetTag("auth.validation.success", false);
            activity?.SetTag("auth.validation.failure_reason", "token_expired");
            activity?.SetTag("auth.validation.session_id", sessionId);

            return new AuthorizationValidationResult(false, null, StatusCode.Unauthenticated, "Token expired.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Token validation failed for session {SessionId}.", sessionId);

            // Record exception and set error status on the current activity
            var activity = Activity.Current;
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, "Token validation failed");
            activity?.SetTag("auth.validation.success", false);
            activity?.SetTag("auth.validation.failure_reason", "validation_failed");
            activity?.SetTag("auth.validation.session_id", sessionId);
            activity?.SetTag("auth.validation.error_type", ex.GetType().Name);

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


