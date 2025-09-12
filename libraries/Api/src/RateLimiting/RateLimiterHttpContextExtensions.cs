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
        string? requestPath = null,
        CancellationToken cancellationToken = default)
    {
        var limiter = context.CreateFixedLimiterByIdentity(windowSeconds, maxRequests, requestPath);
        await context.EnforceAsync(limiter, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public static async Task EnforceFixedByEmailAsync(
        this HttpContext context,
        string email,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ArgumentException("Email must be provided.", nameof(email));
        }

        var limiter = context.CreateFixedLimiterByEmail(email, windowSeconds, maxRequests, requestPath);
        await context.EnforceAsync(limiter, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    public static async Task EnforceFixedByIpAsync(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null,
        CancellationToken cancellationToken = default)
    {
        var limiter = context.CreateFixedLimiterByIp(windowSeconds, maxRequests, requestPath);
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

    private static string GetPath(this HttpContext context)
        => context.Request.Path.ToString();

    private static async Task EnforceAsync(
        this HttpContext context,
        RateLimiter limiter,
        CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity("rate_limit.enforce");
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
            // Extract retry-after information from the lease
            var retryAfterSeconds = 0;
            if (lease.TryGetMetadata("RetryAfter", out var retryAfterObj) && retryAfterObj is int retryAfter)
            {
                retryAfterSeconds = retryAfter;
                activity?.SetTag("rate.limit.retry_after", retryAfterSeconds);
            }

            // Create error message with retry-after information
            var message = retryAfterSeconds > 0
                ? $"Rate limit exceeded. Try again in {Math.Ceiling(retryAfterSeconds / 60.0)} minutes."
                : "Rate limit exceeded.";

            var descriptor = new GrpcErrorDescriptor(
                StatusCode.ResourceExhausted,
                ErrorCodes.ResourceExhausted,
                Message: message);

            var exception = descriptor.ToRpcException();

            // Add retry-after as gRPC metadata
            if (retryAfterSeconds > 0)
            {
                exception.Trailers.Add("retry-after-seconds", retryAfterSeconds.ToString());
            }

            throw exception;
        }
    }

    private static RateLimiter CreateSlidingLimiterByIdentity(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10)
    {
        var userId = context.GetUserIdentifier();
        if (string.IsNullOrWhiteSpace(userId))
        {
            return context.CreateSlidingLimiterByIp(windowSeconds, maxRequests);
        }

        var db = context.GetRedisDb();
        var path = context.GetPath();
        var key = string.IsNullOrEmpty(path)
            ? $"sliding:user:{userId}"
            : $"sliding:{path}:user:{userId}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateSlidingLimiterForIdentifier(
        this HttpContext context,
        string identifier,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var db = context.GetRedisDb();
        var path = requestPath ?? context.GetPath();
        var key = string.IsNullOrEmpty(path)
            ? $"sliding:{identifier}"
            : $"sliding:{path}:{identifier}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateFixedLimiterForIdentifier(
        this HttpContext context,
        string identifier,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var db = context.GetRedisDb();
        var path = requestPath ?? context.GetPath();
        var key = string.IsNullOrEmpty(path)
            ? $"fixed:{identifier}"
            : $"fixed:{path}:{identifier}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateSlidingLimiterByIp(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var db = context.GetRedisDb();
        var path = requestPath ?? context.GetPath();
        var ip = context.GetRemoteIp() ?? "unknown";
        var key = string.IsNullOrEmpty(path)
            ? $"sliding:ip:{ip}"
            : $"sliding:{path}:ip:{ip}";

        return new RedisScriptRateLimiter(db, Scripts.SlidingWindowScript, key, windowSeconds, maxRequests, "sliding");
    }

    private static RateLimiter CreateFixedLimiterByIp(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var db = context.GetRedisDb();
        var path = requestPath ?? context.GetPath();
        var ip = context.GetRemoteIp() ?? "unknown";
        var key = string.IsNullOrEmpty(path)
            ? $"fixed:ip:{ip}"
            : $"fixed:{path}:ip:{ip}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateFixedLimiterByIdentity(
        this HttpContext context,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var userId = context.GetUserIdentifier();
        if (string.IsNullOrWhiteSpace(userId))
        {
            return context.CreateFixedLimiterByIp(windowSeconds, maxRequests, requestPath);
        }

        var db = context.GetRedisDb();
        var path = requestPath ?? context.GetPath();
        var key = string.IsNullOrEmpty(path)
            ? $"fixed:user:{userId}"
            : $"fixed:{path}:user:{userId}";

        return new RedisScriptRateLimiter(db, Scripts.FixedWindowScript, key, windowSeconds, maxRequests, "fixed");
    }

    private static RateLimiter CreateFixedLimiterByEmail(
        this HttpContext context,
        string email,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var normalized = NormalizeEmail(email);
        return context.CreateFixedLimiterForIdentifier($"email:{normalized}", windowSeconds, maxRequests, requestPath);
    }

    private static RateLimiter CreateSlidingLimiterByEmail(
        this HttpContext context,
        string email,
        int windowSeconds = 60,
        int maxRequests = 10,
        string? requestPath = null)
    {
        var normalized = NormalizeEmail(email);
        return context.CreateSlidingLimiterForIdentifier($"email:{normalized}", windowSeconds, maxRequests, requestPath);
    }

    private static string NormalizeEmail(string email)
        => email.Trim().ToLowerInvariant();
}
