using AuthSample.Authentication;

namespace AuthSample.Auth.Core.Identity;

public interface IIdentityService
{
    Task<SignUpStep> InitiateSignUpAsync(InitiateSignUpRequest request, CancellationToken cancellationToken = default);
    Task<ClientSession?> VerifySignUpAndSignInAsync(string emailAddress, string verificationCode, CancellationToken cancellationToken = default);
    Task<ResolvedSession?> ResolveSessionAsync(string? cookieHeader, CancellationToken cancellationToken = default);
}
