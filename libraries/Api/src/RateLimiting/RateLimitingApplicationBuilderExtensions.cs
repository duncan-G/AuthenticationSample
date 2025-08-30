using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;

namespace AuthSample.Api.RateLimiting;

public static class RateLimitingApplicationBuilderExtensions
{
    public static IApplicationBuilder UseSlidingWindowRateLimiting(this IApplicationBuilder app)
    {
        return app.UseMiddleware<RateLimitingMiddleware>(new Func<HttpContext, System.Threading.Tasks.ValueTask<System.Threading.RateLimiting.RateLimiter>>(ctx => ctx.CreateSlidingLimiterAsync()));
    }

    public static IApplicationBuilder UseFixedWindowRateLimiting(this IApplicationBuilder app)
    {
        return app.UseMiddleware<RateLimitingMiddleware>(new Func<HttpContext, System.Threading.Tasks.ValueTask<System.Threading.RateLimiting.RateLimiter>>(ctx => ctx.CreateFixedLimiterAsync()));
    }
}


