using Microsoft.Extensions.DependencyInjection;

namespace AuthenticationSample.Api.Cors;

public static class CorsExtensions
{
    public const string CorsPolicyName = "AllowClient";

    public static IServiceCollection AddAuthenticationSampleCors(
        this IServiceCollection services,
        Action<CorsOptions> configureOptions)
    {
        CorsOptions options = new();
        configureOptions(options);

        services.AddCors(o => o.AddPolicy(CorsPolicyName, policyBuilder =>
        {
            policyBuilder.WithOrigins(options.AllowedOrigins.ToArray())
                .AllowAnyMethod()
                .AllowAnyHeader()
                .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding");
        }));
        
        return services;
    }
}