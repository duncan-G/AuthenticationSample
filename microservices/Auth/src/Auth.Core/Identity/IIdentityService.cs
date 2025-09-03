using AuthSample.Authentication;

namespace AuthSample.Auth.Core.Identity;

public interface IIdentityService
{
    Task<SignUpStep> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task<SessionId> VerifySignUpAndSignInAsync(string emailAddress, string verificationCode, CancellationToken cancellationToken = default);
}
