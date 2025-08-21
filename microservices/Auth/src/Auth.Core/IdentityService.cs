using AuthSample.Auth.Core.Exceptions;
using Microsoft.Extensions.Logging;

namespace AuthSample.Auth.Core;

public class IdentityService(
    IIdentityGateway identityGateway,
    ILogger<IdentityService> logger) : IIdentityService
{
    public async Task<Guid> InitiateSignUpAsync(InitiateSignUpRequest request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userId = await identityGateway.InitiateSignUpAsync(request, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Verification code sent to {EmailAddress}", request.EmailAddress);
            return userId;
        }
        catch (DuplicateEmailException)
        {
            var availability =
                await identityGateway.GetSignUpAvailabilityAsync(request.EmailAddress, cancellationToken).ConfigureAwait(false);

            if (availability.Status != AvailabilityStatus.PendingConfirm)
            {
                throw;
            }

            if (request.Password != null)
            {
                await identityGateway.UpdatePasswordAsync(request, cancellationToken).ConfigureAwait(false);
            }

            await identityGateway.ResendSignUpVerificationAsync(request, cancellationToken).ConfigureAwait(false);
            logger.LogInformation("Resent verification code to {EmailAddress}", request.EmailAddress);
            return availability.UserId ?? Guid.Empty;

        }
    }

    public Task VerifySignUpAsync(string emailAddress, string verificationCode,
        CancellationToken cancellationToken = default)
    {
        return identityGateway.VerifySignUpAsync(
            new VerifySignUpRequest(emailAddress, verificationCode),
            cancellationToken);
    }

    public async Task<bool> IsEmailTakenAsync(string emailAddress, CancellationToken cancellationToken = default)
    {
        var availability = await identityGateway.GetSignUpAvailabilityAsync(emailAddress, cancellationToken).ConfigureAwait(false);
        return availability.Status == AvailabilityStatus.AlreadySignedUp;
    }
}
