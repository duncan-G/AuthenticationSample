using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Metadata;

namespace AuthSample.Api.RateLimiting;

public sealed class EmailRateLimitingEndpointFilter(string emailArgumentName = "email", bool useSlidingWindow = true) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;

        var email = ExtractEmailFromArguments(context, emailArgumentName);
        if (!string.IsNullOrWhiteSpace(email))
        {
            var identifier = $"email:{email.Trim().ToLowerInvariant()}";
            var limiter = useSlidingWindow
                ? httpContext.CreateSlidingLimiterForIdentifier(identifier)
                : httpContext.CreateFixedLimiterForIdentifier(identifier);

            using var lease = await limiter.AcquireAsync(1, httpContext.RequestAborted).ConfigureAwait(false);
            if (!lease.IsAcquired)
            {
                return Results.StatusCode(StatusCodes.Status429TooManyRequests);
            }
        }

        return await next(context).ConfigureAwait(false);
    }

    private static string? ExtractEmailFromArguments(EndpointFilterInvocationContext context, string emailArgumentName)
    {
        foreach (var arg in context.Arguments)
        {
            if (arg is null)
            {
                continue;
            }

            if (arg is string strArg && string.Equals(emailArgumentName, "email", StringComparison.OrdinalIgnoreCase))
            {
                return strArg;
            }

            var prop = arg.GetType().GetProperty(emailArgumentName, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.IgnoreCase);
            if (prop is not null && prop.PropertyType == typeof(string))
            {
                var val = prop.GetValue(arg) as string;
                if (!string.IsNullOrWhiteSpace(val))
                {
                    return val;
                }
            }
        }

        return null;
    }
}


