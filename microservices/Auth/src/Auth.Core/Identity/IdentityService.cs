using System.Security.Cryptography;
using System.Text.Json;
using AuthSample.Auth.Core.Exceptions;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace AuthSample.Auth.Core.Identity;

public class IdentityService(
    IConnectionMultiplexer  cache,
    IIdentityGateway identityGateway,
    ILogger<IdentityService> logger) : IIdentityService
{
    private readonly IDatabase _cacheDb = cache.GetDatabase();

    public async Task<SignUpStep> InitiateSignUpAsync(InitiateSignUpRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.RequirePassword)
        {
            return await InitiatePasswordSignUpAsync(request, cancellationToken).ConfigureAwait(false);
        }

        return await InitiatePasswordlessSignUpAsync(request, cancellationToken).ConfigureAwait(false);
    }

    public async Task<SessionId> VerifySignUpAndSignInAsync(string emailAddress, string verificationCode,
        CancellationToken cancellationToken = default)
    {
        var signUpSession = await identityGateway.VerifySignUpAsync(
            new VerifySignUpRequest(emailAddress, verificationCode),
            cancellationToken).ConfigureAwait(false);

        var sessionData = await identityGateway.InitiateAuthAsync(emailAddress, signUpSession, cancellationToken).ConfigureAwait(false);
        var sessionId = GenerateSessionId();
        var cacheKey = $"sess:{sessionId}";
        var payload = JsonSerializer.Serialize(sessionData);
        var ttl = sessionData.Expiry - DateTime.UtcNow;

        await _cacheDb.StringSetAsync(cacheKey, payload, ttl).ConfigureAwait(false);

        return new SessionId(sessionId, sessionData.Expiry);
    }

    private async Task<SignUpStep> InitiatePasswordSignUpAsync(InitiateSignUpRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!request.RequirePassword)
        {
            return await InitiatePasswordlessSignUpAsync(request, cancellationToken).ConfigureAwait(false);
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
                    await identityGateway.ResendSignUpVerificationAsync(request, cancellationToken).ConfigureAwait(false);
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

            await identityGateway.ConfirmUserAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Resent verification code to {EmailAddress}", request.EmailAddress);

            return SignUpStep.VerificationRequired;
        }
    }

    private async Task<SignUpStep> InitiatePasswordlessSignUpAsync(InitiateSignUpRequest request,
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

            await identityGateway.ConfirmUserAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Resent verification code to {EmailAddress}", request.EmailAddress);

            return SignUpStep.VerificationRequired;
        }
    }

    private static string GenerateSessionId(int numBytes = 32)
    {
        var bytes = RandomNumberGenerator.GetBytes(numBytes);
        var base64 = Convert.ToBase64String(bytes);
        return base64.Replace('+', '-').Replace('/', '_').TrimEnd('=');
    }
}
