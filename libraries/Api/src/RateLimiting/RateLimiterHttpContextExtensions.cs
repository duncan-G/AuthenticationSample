using System.Diagnostics;
using System.Security.Claims;
using System.Threading.RateLimiting;
using AuthSample.Exceptions;
using Grpc.Core;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

public static class RateLimiterHttpContextExtensions
{
    private static readonly ActivitySource ActivitySource = new("AuthSample.Api.RateLimiting");

    public static async Task EnforceFixedByIdentityAsync(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        bool includeMethod = true,
        CancellationToken cancellationToken = default)
    {
        var limiter = context.CreateFixedLimiterByIdentity(includeMethod, windowSeconds, maxRequests);
        await context.EnforceAsync(limiter, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public static async Task EnforceFixedByEmailAsync(
        this HttpContext context,
        string email,
        int windowSeconds = 60,
        int maxRequests = 10,
        bool includeMethod = true,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ArgumentException("Email must be provided.", nameof(email));
        }

        var limiter = context.CreateFixedLimiterByEmail(email, includeMethod, windowSeconds, maxRequests);
        await context.EnforceAsync(limiter, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public static async Task EnforceFixedByIpAsync(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        bool includeMethod = true,
        CancellationToken cancellationToken = default)
    {
        var limiter = context.CreateFixedLimiterByIp(includeMethod, windowSeconds, maxRequests);
        await context.EnforceAsync(limiter, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    private static string? GetUserIdentifier(this HttpContext context)
    {
        // Return the subject claim if authenticated; otherwise null (fallback to IP is handled by callers).
        return context.User.Identity?.IsAuthenticated == true ? context.User.FindFirstValue("sub") : null;
    }

    private static string? GetRemoteIp(this HttpContext context)
        => context.Connection.RemoteIpAddress?.ToString();

    private static IDatabase GetRedisDb(this HttpContext context)
    {
        var sp = context.RequestServices;
        var mux = sp.GetRequiredService<IConnectionMultiplexer>();
        return mux.GetDatabase();
    }

    private static async Task<bool> TryAcquireAsync(
        this HttpContext context,
        RateLimiter limiter,
        CancellationToken cancellationToken = default)
    {
        using var lease = await limiter.AcquireAsync(1, cancellationToken).ConfigureAwait(false);
        return lease.IsAcquired;
    }

    private static string GetMethodSegment(this HttpContext context, bool includeMethod)
        => includeMethod ? context.Request.Path.ToString() : string.Empty;

    private static async Task EnforceAsync(
        this HttpContext context,
        RateLimiter limiter,
        CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity("rate_limit.enforce", ActivityKind.Internal);
        activity?.SetTag("http.request.method", context.Request.Method);
        activity?.SetTag("http.route", context.Request.Path.ToString());
        var userId = context.GetUserIdentifier();
        if (!string.IsNullOrWhiteSpace(userId))
        {
            activity?.SetTag("enduser.id", userId);
        }
        var ip = context.GetRemoteIp();
        if (!string.IsNullOrWhiteSpace(ip))
        {
            activity?.SetTag("client.address", ip);
        }

        using var lease = await limiter.AcquireAsync(1, cancellationToken).ConfigureAwait(false);
        if (!lease.IsAcquired)
        {
            var descriptor = new GrpcErrorDescriptor(
                StatusCode.ResourceExhausted,
                ErrorCodes.ResourceExhausted,
                Message: "Resource exhausted.");
            throw descriptor.ToRpcException();
        }
    }

    private static RateLimiter CreateSlidingLimiterByIdentity(
        this HttpContext context,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var userId = context.GetUserIdentifier();
        if (string.IsNullOrWhiteSpace(userId))
        {
            return context.CreateSlidingLimiterByIp(includeMethod, windowSeconds, maxRequests);
        }

        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var key = string.IsNullOrEmpty(method)
            ? $"sliding:user:{userId}"
            : $"sliding:{method}:user:{userId}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateSlidingLimiterForIdentifier(
        this HttpContext context,
        string identifier,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var key = string.IsNullOrEmpty(method)
            ? $"sliding:{identifier}"
            : $"sliding:{method}:{identifier}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateFixedLimiterForIdentifier(
        this HttpContext context,
        string identifier,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var key = string.IsNullOrEmpty(method)
            ? $"fixed:{identifier}"
            : $"fixed:{method}:{identifier}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateSlidingLimiterByIp(
        this HttpContext context,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var ip = context.GetRemoteIp() ?? "unknown";
        var key = string.IsNullOrEmpty(method)
            ? $"sliding:ip:{ip}"
            : $"sliding:{method}:ip:{ip}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateFixedLimiterByIp(
        this HttpContext context,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var ip = context.GetRemoteIp() ?? "unknown";
        var key = string.IsNullOrEmpty(method)
            ? $"fixed:ip:{ip}"
            : $"fixed:{method}:ip:{ip}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateFixedLimiterByIdentity(
        this HttpContext context,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var userId = context.GetUserIdentifier();
        if (string.IsNullOrWhiteSpace(userId))
        {
            return context.CreateFixedLimiterByIp(includeMethod, windowSeconds, maxRequests);
        }

        var db = context.GetRedisDb();
        var method = context.GetMethodSegment(includeMethod);
        var key = string.IsNullOrEmpty(method)
            ? $"fixed:user:{userId}"
            : $"fixed:{method}:user:{userId}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateFixedLimiterByEmail(
        this HttpContext context,
        string email,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var normalized = NormalizeEmail(email);
        return context.CreateFixedLimiterForIdentifier($"email:{normalized}", includeMethod, windowSeconds, maxRequests);
    }

    private static RateLimiter CreateSlidingLimiterByEmail(
        this HttpContext context,
        string email,
        bool includeMethod = true,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var normalized = NormalizeEmail(email);
        return context.CreateSlidingLimiterForIdentifier($"email:{normalized}", includeMethod, windowSeconds, maxRequests);
    }

    private static string NormalizeEmail(string email)
        => email.Trim().ToLowerInvariant();
}
