using AuthSample.Auth.Grpc;
using Microsoft.Extensions.DependencyInjection;

namespace AuthSample.Authentication;

public static class AuthenticationServiceCollectionExtensions
{
    public static IServiceCollection AddAuthnAuthz(
        this IServiceCollection services,
        Action<AuthOptions> configureOptions)
    {
        services
            .Configure(configureOptions)
            .AddSingleton<TokenValidationParametersHelper>();
        return services;
    }
}
