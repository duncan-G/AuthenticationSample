using Microsoft.Extensions.DependencyInjection;

namespace AuthSample.Api.Cors;

public static class CorsExtensions
{
    public const string CorsPolicyName = "AllowClient";

    public static IServiceCollection AddAuthSampleCors(
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
                .WithExposedHeaders("Grpc-Status", "Grpc-Message", "Grpc-Encoding", "Grpc-Accept-Encoding", "Error-Code");
        }));

        return services;
    }
}
