namespace AuthSample.Auth.Core;

public interface IIdentityGateway
{
    Task<SignUpAvailability> GetSignUpAvailabilityAsync(string emailAddress,
        CancellationToken cancellationToken = default);

    Task<Guid> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task VerifySignUpAsync(VerifySignUpRequest request, CancellationToken cancellationToken = default);
    Task ResendSignUpVerificationAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);

    Task UpdatePasswordAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
}
