namespace AuthSample.Auth.Core;

public interface IIdentityService
{
    Task<Guid> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task VerifySignUpAsync(string emailAddress, string verificationCode, CancellationToken cancellationToken = default);
    Task<bool> IsEmailTakenAsync(string emailAddress, CancellationToken cancellationToken = default);
}
