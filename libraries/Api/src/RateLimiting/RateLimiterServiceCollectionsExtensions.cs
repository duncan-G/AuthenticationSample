using Microsoft.Extensions.Caching.StackExchangeRedis;
using Microsoft.Extensions.DependencyInjection;
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
            ConnectionMultiplexer.Connect(redisOptions.Configuration ?? throw new InvalidOperationException("Configuration is null")));
        return services;
    }
}
