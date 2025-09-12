using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography;
using System.Text.Json;
using AuthSample.Auth.Core.Exceptions;
using AuthSample.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using StackExchange.Redis;

namespace AuthSample.Auth.Core.Identity;

public class IdentityService(
    IConnectionMultiplexer cache,
    IOptions<AuthOptions> authOptions,
    IIdentityGateway identityGateway,
    IRefreshTokenStore refreshTokenStore,
    TokenValidationParametersHelper tokenParameterHelper,
    ISignUpEligibilityGuard signUpEligibilityGuard,
    ILogger<IdentityService> logger) : IIdentityService
{
    private readonly IDatabase _cacheDb = cache.GetDatabase();

    public async Task<SignUpStep> InitiateSignUpAsync(
        InitiateSignUpRequest request,
        Func<Task> enforceVerificationRateLimit,
        CancellationToken cancellationToken = default)
    {
        if (request.RequirePassword)
        {
            return await InitiatePasswordSignUpAsync(request, enforceVerificationRateLimit, cancellationToken).ConfigureAwait(false);
        }

        return await InitiatePasswordlessSignUpAsync(request, enforceVerificationRateLimit, cancellationToken).ConfigureAwait(false);
    }

    public async Task<ClientSession?> VerifySignUpAndSignInAsync(string emailAddress, string verificationCode,
        CancellationToken cancellationToken = default)
    {
        string signUpSession;
        try
        {
            signUpSession = await identityGateway.VerifySignUpAsync(
                new VerifySignUpRequest(emailAddress, verificationCode),
                cancellationToken).ConfigureAwait(false);
        }
        catch (UserAlreadyConfirmedException)
        {
            return null;
        }

        try
        {
            var session = await SignInAsync(emailAddress, signUpSession, cancellationToken).ConfigureAwait(false);
            await signUpEligibilityGuard.IncrementConfirmedUsersAsync(cancellationToken).ConfigureAwait(false);
            return session;
        }
        catch  (Exception ex)
        {
            logger.LogError(ex, "Failed to sign up after sign up.");
            return null;
        }
    }

    public async Task<ResolvedSession?> ResolveSessionAsync(
        string? cookieHeader,
        CancellationToken cancellationToken = default)
    {
        var accessTokenSessionId = ParseCookie(cookieHeader, "AT_SID");

        var cacheKey = $"sess:{accessTokenSessionId}";
        if (!string.IsNullOrEmpty(accessTokenSessionId))
        {
            var sessionJson = await _cacheDb.StringGetAsync(cacheKey).ConfigureAwait(false);
            if (sessionJson.HasValue)
            {
                var sessionData = JsonSerializer.Deserialize<SessionData>(sessionJson.ToString());
                if (sessionData != null)
                {
                    try
                    {
                        var validationParameters = await tokenParameterHelper.GetTokenValidationParameters(cancellationToken).ConfigureAwait(false);

                        var handler = new JwtSecurityTokenHandler();
                        var token = handler.ReadJwtToken(sessionData.AccessToken);
                        var clientIdClaim = token.Claims.FirstOrDefault(c => c.Type == "client_id")?.Value;

                        handler.ValidateToken(sessionData.AccessToken, validationParameters, out _);

                        if (string.IsNullOrEmpty(clientIdClaim) || clientIdClaim != authOptions.Value.Audience)
                        {
                            throw new SecurityTokenValidationException("Invalid or missing client_id claim");
                        }

                        return new ResolvedSession(sessionData, null, null, false);
                    }
                    catch (SecurityTokenExpiredException)
                    {
                        // proceed to refresh path
                    }
                    catch (Exception ex)
                    {
                        logger.LogWarning(ex, "Token validation failed; attempting refresh if possible");
                        // proceed to refresh path
                    }
                }
            }
        }

        // Refresh path
        var refreshTokenId = ParseCookie(cookieHeader, "RT_SID");
        if (string.IsNullOrWhiteSpace(refreshTokenId))
        {
            return null;
        }

        var refreshRecord = await refreshTokenStore.GetAsync(refreshTokenId, cancellationToken).ConfigureAwait(false);
        if (refreshRecord is null)
        {
            // Invalid RT_SID, instruct caller to clear refresh cookie
            return new ResolvedSession(null, null, null, true);
        }

        try
        {
            var refreshed = await identityGateway.RefreshSessionAsync(refreshRecord, cancellationToken).ConfigureAwait(false);
            var sessionToCache = refreshed with { RefreshToken = string.Empty, Sub = refreshRecord.UserSub };
            var payload = JsonSerializer.Serialize(sessionToCache);
            var ttl = sessionToCache.AccessTokenExpiry - DateTime.UtcNow;
            if (ttl <= TimeSpan.Zero) ttl = TimeSpan.FromSeconds(1);

            // If AT_SID is missing, create a new one
            if (string.IsNullOrEmpty(accessTokenSessionId))
            {
                accessTokenSessionId = GenerateSessionId();
                cacheKey = $"sess:{accessTokenSessionId}";
            }

            await _cacheDb.StringSetAsync(cacheKey, payload, ttl).ConfigureAwait(false);
            return new ResolvedSession(sessionToCache, accessTokenSessionId, sessionToCache.AccessTokenExpiry, false);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to refresh session from cookies");
            return null;
        }
    }

    public async Task ResendVerificationCodeAsync(string emailAddress, System.Net.IPAddress ipAddress, CancellationToken cancellationToken = default)
    {
        using var activity = System.Diagnostics.Activity.Current?.Source.StartActivity("IdentityService.ResendVerificationCode");
        activity?.SetTag("email.domain", emailAddress.Split('@').LastOrDefault());
        activity?.SetTag("ip.address", ipAddress.ToString());

        logger.LogInformation("Initiating resend verification code request for {EmailAddress} from {IpAddress}",
            emailAddress, ipAddress);

        try
        {
            await identityGateway.ResendSignUpVerificationAsync(emailAddress, ipAddress, cancellationToken).ConfigureAwait(false);

            logger.LogInformation("Successfully resent verification code to {EmailAddress} from {IpAddress}",
                emailAddress, ipAddress);

            activity?.SetTag("resend.result", "success");
        }
        catch (VerificationCodeDeliveryFailedException ex)
        {
            logger.LogError(ex, "Failed to deliver verification code to {EmailAddress} from {IpAddress}: {ErrorMessage}",
                emailAddress, ipAddress, ex.Message);

            activity?.SetTag("resend.result", "delivery_failed");
            activity?.SetTag("error.type", "delivery_failure");
            throw;
        }
        catch (VerificationCodeDeliveryTooSoonException ex)
        {
            logger.LogWarning("Resend verification code attempted too soon for {EmailAddress} from {IpAddress}: {ErrorMessage}",
                emailAddress, ipAddress, ex.Message);

            activity?.SetTag("resend.result", "too_soon");
            activity?.SetTag("error.type", "rate_limited");
            throw;
        }
        catch (UserWithEmailNotFoundException)
        {
            logger.LogWarning("Attempted to resend verification code for non-existent user {EmailAddress} from {IpAddress}",
                emailAddress, ipAddress);

            activity?.SetTag("resend.result", "user_not_found");
            activity?.SetTag("error.type", "user_not_found");
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error while resending verification code to {EmailAddress} from {IpAddress}: {ErrorMessage}",
                emailAddress, ipAddress, ex.Message);

            activity?.SetTag("resend.result", "error");
            activity?.SetTag("error.type", "unexpected");
            activity?.SetTag("error.message", ex.Message);
            throw;
        }
    }

    private async Task<SignUpStep> InitiatePasswordSignUpAsync(
        InitiateSignUpRequest request,
        Func<Task> enforceVerificationRateLimit,
        CancellationToken cancellationToken = default)
    {
        if (!request.RequirePassword)
        {
            return await InitiatePasswordlessSignUpAsync(request, enforceVerificationRateLimit, cancellationToken).ConfigureAwait(false);
        }

        // When a password is required but no password has been passed then we are
        // in the initial step of sign up where we validate whether the email address
        //  is available.
        if (string.IsNullOrEmpty(request.Password))
        {
            var availability = await identityGateway.GetSignUpAvailabilityAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);
            switch (availability.Status)
            {
                case AvailabilityStatus.NewUser:
                    return SignUpStep.PasswordRequired;
                case AvailabilityStatus.PendingConfirm:
                    await enforceVerificationRateLimit().ConfigureAwait(false);
                    await identityGateway.ResendSignUpVerificationAsync(
                        request.EmailAddress, request.IpAddress, cancellationToken).ConfigureAwait(false);
                    return SignUpStep.VerificationRequired;
                case AvailabilityStatus.AlreadySignedUp:
                    throw new DuplicateEmailException();
                default:
                    throw new NotSupportedException();
            }
        }

        try
        {
            await identityGateway.InitiateSignUpAsync(request, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Verification code sent to {EmailAddress}", request.EmailAddress);
            return SignUpStep.VerificationRequired;
        }
        catch (DuplicateEmailException)
        {
            var availability =
                await identityGateway.GetSignUpAvailabilityAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);

            if (availability.Status != AvailabilityStatus.PendingConfirm)
            {
                throw;
            }

            await enforceVerificationRateLimit().ConfigureAwait(false);
            await identityGateway.ResendSignUpVerificationAsync(
                request.EmailAddress, request.IpAddress, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Resent verification code to {EmailAddress}", request.EmailAddress);

            return SignUpStep.VerificationRequired;
        }
    }

    private async Task<SignUpStep> InitiatePasswordlessSignUpAsync(
        InitiateSignUpRequest request,
        Func<Task> enforceVerificationRateLimit,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await identityGateway.InitiateSignUpAsync(request, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Verification code sent to {EmailAddress}", request.EmailAddress);
            return SignUpStep.VerificationRequired;
        }
        catch (DuplicateEmailException)
        {
            var availability =
                await identityGateway.GetSignUpAvailabilityAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);

            if (availability.Status != AvailabilityStatus.PendingConfirm)
            {
                throw;
            }

            await enforceVerificationRateLimit().ConfigureAwait(false);
            await identityGateway.ResendSignUpVerificationAsync(
                request.EmailAddress, request.IpAddress, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Resent verification code to {EmailAddress}", request.EmailAddress);

            return SignUpStep.VerificationRequired;
        }
    }

    private async Task<ClientSession> SignInAsync(string emailAddress, string signUpSession,
        CancellationToken cancellationToken)
    {
        var sessionData = await identityGateway.InitiateAuthAsync(emailAddress, signUpSession, cancellationToken)
            .ConfigureAwait(false);

        // Generate opaque refresh-session id
        var refreshTokenId = GenerateSessionId();

        // Persist the refresh token with rtId
        await refreshTokenStore.SaveAsync(
            new RefreshTokenRecord(
                refreshTokenId,
                sessionData.Sub,
                sessionData.Email,
                sessionData.RefreshToken,
                sessionData.IssuedAt,
                sessionData.RefreshTokenExpiry),
            cancellationToken).ConfigureAwait(false);

        // Remove refresh token from cached session
        var cachedSession = sessionData with { RefreshToken = string.Empty };

        // Cache access session
        var tokenId = GenerateSessionId();
        var cacheKey = $"sess:{tokenId}";
        var payload = JsonSerializer.Serialize(cachedSession);
        var ttl = cachedSession.AccessTokenExpiry - DateTime.UtcNow;
        await _cacheDb.StringSetAsync(cacheKey, payload, ttl).ConfigureAwait(false);

        return new ClientSession(
            tokenId,
            cachedSession.AccessTokenExpiry,
            refreshTokenId,
            cachedSession.RefreshTokenExpiry);
    }

    private static string GenerateSessionId(int numBytes = 32)
    {
        var bytes = RandomNumberGenerator.GetBytes(numBytes);
        var base64 = Convert.ToBase64String(bytes);
        return base64.Replace('+', '-').Replace('/', '_').TrimEnd('=');
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
