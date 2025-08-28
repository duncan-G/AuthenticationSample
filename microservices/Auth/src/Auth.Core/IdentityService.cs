using AuthSample.Auth.Core.Exceptions;
using Microsoft.Extensions.Logging;

namespace AuthSample.Auth.Core;

public class IdentityService(
    IIdentityGateway identityGateway,
    ILogger<IdentityService> logger) : IIdentityService
{
    public async Task<SignUpStep> InitiateSignUpAsync(InitiateSignUpRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.RequirePassword)
        {
            return await InitiatePasswordSignUpAsync(request, cancellationToken).ConfigureAwait(false);
        }

        return await InitiatePasswordlessSignUpAsync(request, cancellationToken).ConfigureAwait(false);
    }

    public async Task VerifySignUpAndSignInAsync(string emailAddress, string verificationCode,
        CancellationToken cancellationToken = default)
    {
        var session = await identityGateway.VerifySignUpAsync(
            new VerifySignUpRequest(emailAddress, verificationCode),
            cancellationToken).ConfigureAwait(false);

        await identityGateway.InitiateAuthAsync(emailAddress, session, cancellationToken).ConfigureAwait(false);
    }

    public async Task<bool> IsEmailTakenAsync(string emailAddress, CancellationToken cancellationToken = default)
    {
        var availability = await identityGateway.GetSignUpAvailabilityAsync(emailAddress, cancellationToken).ConfigureAwait(false);
        return availability.Status == AvailabilityStatus.AlreadySignedUp;
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
                    throw new DuplicateEmailException(request.EmailAddress);
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
}
