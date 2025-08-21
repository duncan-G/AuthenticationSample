using Microsoft.Extensions.DependencyInjection;

namespace AuthSample.Authentication;

public static class AuthenticationServiceCollectionExtensions
{
    public static IServiceCollection AddAuthnAuthz(
        this IServiceCollection services,
        Action<AuthOptions> configureOptions)
    {
        // TODO: Add Authn and Authz services here.
        services.Configure(configureOptions);
        return services;
    }
}
