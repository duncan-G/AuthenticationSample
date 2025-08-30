using System.Threading.RateLimiting;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

public static class RateLimitingHttpContextExtensions
{
    public static ValueTask<RateLimiter> CreateSlidingLimiterAsync(this HttpContext httpContext)
    {
        var sp = httpContext.RequestServices;
        var opts = sp.GetRequiredService<IOptions<RedisRateLimitingOptions>>().Value;
        var mux = sp.GetRequiredService<IConnectionMultiplexer>();
        var db = mux.GetDatabase();
        var route = httpContext.Request.Path.ToString();
        var identifier = GetRateLimitIdentifier(httpContext);
        var key = $"sliding:{route}:{identifier}";
        return ValueTask.FromResult<RateLimiter>(new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, opts.SlidingWindowSeconds, opts.SlidingMaxRequests));
    }

    public static ValueTask<RateLimiter> CreateFixedLimiterAsync(this HttpContext httpContext)
    {
        var sp = httpContext.RequestServices;
        var opts = sp.GetRequiredService<IOptions<RedisRateLimitingOptions>>().Value;
        var mux = sp.GetRequiredService<IConnectionMultiplexer>();
        var db = mux.GetDatabase();
        var route = httpContext.Request.Path.ToString();
        var identifier = GetRateLimitIdentifier(httpContext);
        var key = $"fixed:{route}:{identifier}";
        return ValueTask.FromResult<RateLimiter>(new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, opts.FixedWindowSeconds, opts.FixedMaxRequests));
    }

    public static RateLimiter CreateSlidingLimiterForIdentifier(this HttpContext httpContext, string identifier)
    {
        var sp = httpContext.RequestServices;
        var opts = sp.GetRequiredService<IOptions<RedisRateLimitingOptions>>().Value;
        var mux = sp.GetRequiredService<IConnectionMultiplexer>();
        var db = mux.GetDatabase();
        var route = httpContext.Request.Path.ToString();
        var key = $"sliding:{route}:{identifier}";
        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, opts.SlidingWindowSeconds, opts.SlidingMaxRequests);
    }

    public static RateLimiter CreateFixedLimiterForIdentifier(this HttpContext httpContext, string identifier)
    {
        var sp = httpContext.RequestServices;
        var opts = sp.GetRequiredService<IOptions<RedisRateLimitingOptions>>().Value;
        var mux = sp.GetRequiredService<IConnectionMultiplexer>();
        var db = mux.GetDatabase();
        var route = httpContext.Request.Path.ToString();
        var key = $"fixed:{route}:{identifier}";
        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, opts.FixedWindowSeconds, opts.FixedMaxRequests);
    }

    private static string GetRateLimitIdentifier(HttpContext httpContext)
    {
        var userIdentifier = GetUserIdentifierFromPrincipal(httpContext.User);
        if (!string.IsNullOrWhiteSpace(userIdentifier))
        {
            return $"user:{userIdentifier}";
        }

        var authHeader = httpContext.Request.Headers.Authorization.ToString();
        if (!string.IsNullOrWhiteSpace(authHeader))
        {
            return $"auth:{authHeader}";
        }

        var ip = httpContext.Connection.RemoteIpAddress?.ToString();
        if (!string.IsNullOrWhiteSpace(ip))
        {
            return $"ip:{ip}";
        }

        return "anon";
    }

    private static string? GetUserIdentifierFromPrincipal(ClaimsPrincipal? user)
    {
        if (user?.Identity?.IsAuthenticated != true)
        {
            return null;
        }

        return user.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? user.FindFirstValue("sub")
               ?? user.FindFirstValue(ClaimTypes.Email)
               ?? user.Identity?.Name;
    }

    // Body parsing intentionally omitted here. Per-email limiting should be applied via filters after model binding.
}


