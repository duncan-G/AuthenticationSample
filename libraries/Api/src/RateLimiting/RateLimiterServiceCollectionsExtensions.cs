using Microsoft.Extensions.Caching.StackExchangeRedis;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

public static class RateLimiterServiceCollectionsExtensions
{
    public static IServiceCollection AddRedisRateLimiter(
        this IServiceCollection services,
        Action<RedisCacheOptions> configureOptions)
    {
        var redisOptions = new RedisCacheOptions();
        configureOptions.Invoke(redisOptions);

        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger("Redis");

            var configuration = redisOptions.Configuration ??
                                throw new InvalidOperationException("Configuration is null");

            var mux = ConnectionMultiplexer.Connect(configuration, options => options.AbortOnConnectFail = false);

            mux.ConnectionFailed += (_, e) =>
                logger.LogWarning("Redis connection failed: {FailureType} {EndPoint}", e.FailureType, e.EndPoint);
            mux.ConnectionRestored += (_, e) =>
                logger.LogInformation("Redis connection restored: {EndPoint}", e.EndPoint);

            return mux;
        });
        return services;
    }
}
