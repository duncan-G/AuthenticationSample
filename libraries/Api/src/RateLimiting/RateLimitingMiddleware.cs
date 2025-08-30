using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http;

namespace AuthSample.Api.RateLimiting;

public sealed class RateLimitingMiddleware(RequestDelegate next, Func<HttpContext, ValueTask<RateLimiter>> limiterFactory)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var limiter = await limiterFactory(context).ConfigureAwait(false);
        using var lease = await limiter.AcquireAsync(1, context.RequestAborted).ConfigureAwait(false);
        if (!lease.IsAcquired)
        {
            context.Response.StatusCode = StatusCodes.Status429TooManyRequests;
            return;
        }

        await next(context).ConfigureAwait(false);
    }
}


