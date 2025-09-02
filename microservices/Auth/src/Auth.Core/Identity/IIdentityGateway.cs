namespace AuthSample.Auth.Core.Identity;

public interface IIdentityGateway
{
    Task<SignUpAvailability> GetSignUpAvailabilityAsync(string emailAddress,
        CancellationToken cancellationToken = default);

    Task<Guid> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task<string> VerifySignUpAsync(VerifySignUpRequest request, CancellationToken cancellationToken = default);
    Task ResendSignUpVerificationAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task ConfirmUserAsync(string emailAddress, CancellationToken cancellationToken = default);

    Task InitiateAuthAsync(string emailAddress, string sessionId, CancellationToken cancellationToken = default);
}
