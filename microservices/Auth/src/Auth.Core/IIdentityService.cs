namespace AuthSample.Auth.Core;

public interface IIdentityService
{
    Task<SignUpStep> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task VerifySignUpAndSignInAsync(string emailAddress, string verificationCode, CancellationToken cancellationToken = default);
}
