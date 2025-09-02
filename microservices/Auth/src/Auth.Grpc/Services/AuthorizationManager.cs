using System.Text.Json;
using Google.Rpc;
using Grpc.Core;
using StackExchange.Redis;
using System.IdentityModel.Tokens.Jwt;
using Envoy.Service.Auth.V3;
using AuthSample.Authentication;
using Microsoft.IdentityModel.Tokens;

namespace AuthSample.Auth.Grpc.Services;

public sealed class AuthorizationManager(
    IConnectionMultiplexer cache,
    TokenValidationParametersHelper tokenParameterHelper,
    ILogger<AuthorizationManager> logger) : Authorization.AuthorizationBase
{
    private readonly IDatabase _redisDb = cache.GetDatabase();

    public override async Task<CheckResponse> Check(CheckRequest request, ServerCallContext context)
    {
        // 1. Extract the session cookie
        var cookieHeader = request.Attributes.Request.Http.Headers
            .FirstOrDefault(h => h.Key.Equals("cookie", StringComparison.OrdinalIgnoreCase)).Value;

        var sessionId = ParseCookie(cookieHeader, "AT_SID");

        if (string.IsNullOrEmpty(sessionId))
        {
            logger.LogInformation("No AT_SID cookie found, denying access.");
            return DeniedResponse(StatusCode.Unauthenticated, "Session cookie missing.");
        }

        // 2. Retrieve session from Redis
        var sessionJson = await _redisDb.StringGetAsync($"sess:{sessionId}").ConfigureAwait(false);
        if (!sessionJson.HasValue)
        {
            logger.LogWarning("Session ID {SessionId} not found in Redis, denying access.", sessionId);
            return DeniedResponse(StatusCode.Unauthenticated, "Session not found.");
        }

        var sessionData = JsonSerializer.Deserialize<SessionData>(sessionJson.ToString());
        if (sessionData == null)
        {
            logger.LogError("Failed to deserialize session data for {SessionId}.", sessionId);
            return DeniedResponse(StatusCode.Internal, "Invalid session data.");
        }

        // 3. Validate the access token
        try
        {
            var validationParameters = await tokenParameterHelper.GetTokenValidationParameters().ConfigureAwait(false);
            var handler = new JwtSecurityTokenHandler();
            handler.ValidateToken(sessionData.AccessToken, validationParameters, out _);
            logger.LogInformation("Token validated for user {Subject}, allowing access.", sessionData.Sub);
            return AllowedResponse(sessionData);
        }
        catch (SecurityTokenExpiredException ex)
        {
            logger.LogWarning(ex, "Token expired for session {SessionId}.", sessionId);
            return DeniedResponse(StatusCode.Unauthenticated, "Token expired.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Token validation failed for session {SessionId}.", sessionId);
            return DeniedResponse(StatusCode.PermissionDenied, "Token validation failed.");
        }
    }

    private static CheckResponse AllowedResponse(SessionData data)
    {
        var okResponse = new OkHttpResponse();
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "x-user-sub", Value = data.Sub } });
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "x-user-email", Value = data.Email } });

        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)Code.Ok },
            OkResponse = okResponse
        };
    }

    private static CheckResponse DeniedResponse(StatusCode statusCode, string message)
    {
        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)statusCode, Message = message }
        };
    }

    private static string? ParseCookie(string? cookieHeader, string cookieName)
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
