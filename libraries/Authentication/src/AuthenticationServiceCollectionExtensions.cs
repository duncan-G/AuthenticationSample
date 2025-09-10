using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
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

        services
            .AddAuthentication(options =>
            {
                options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
            })
            .AddJwtBearer();

        services
            .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<TokenValidationParametersHelper>(
                (jwt, helper) =>
                {
                    jwt.RequireHttpsMetadata = true;
                    jwt.SaveToken = false;
                    jwt.TokenValidationParameters = helper.GetTokenValidationParameters().GetAwaiter().GetResult();
                });

        services.AddAuthorization(options =>
        {
            options.DefaultPolicy = new AuthorizationPolicyBuilder(JwtBearerDefaults.AuthenticationScheme)
                .RequireAuthenticatedUser()
                .Build();
        });
        return services;
    }
}
