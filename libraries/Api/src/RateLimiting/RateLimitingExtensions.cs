using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

public static class RateLimitingExtensions
{
    public const string SlidingPolicy = "sliding";
    public const string FixedPolicy = "fixed";

    public static IServiceCollection AddRedisRateLimiting(
        this IServiceCollection services,
        Action<RedisRateLimitingOptions> configure)
    {
        services.Configure(configure);

        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            var opts = sp.GetRequiredService<IOptions<RedisRateLimitingOptions>>().Value;
            return ConnectionMultiplexer.Connect(opts.Configuration);
        });

        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        });

        return services;
    }

    public static IApplicationBuilder UseRedisRateLimiting(this IApplicationBuilder app)
    {
        app.UseRateLimiter();
        return app;
    }
}
