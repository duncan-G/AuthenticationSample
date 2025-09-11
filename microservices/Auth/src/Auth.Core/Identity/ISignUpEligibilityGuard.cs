namespace AuthSample.Auth.Core.Identity;

public interface ISignUpEligibilityGuard
{
    Task EnforceMaxConfirmedUsersAsync(CancellationToken cancellationToken = default);

    Task IncrementConfirmedUsersAsync(CancellationToken cancellationToken = default);
}
