using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace AuthSample.Api.RateLimiting;

public sealed class EmailRateLimitingActionFilter : IActionFilter
{
    private readonly string _emailArgumentName;
    private readonly bool _useSlidingWindow;

    public EmailRateLimitingActionFilter(string emailArgumentName = "email", bool useSlidingWindow = true)
    {
        _emailArgumentName = emailArgumentName;
        _useSlidingWindow = useSlidingWindow;
    }

    public void OnActionExecuting(ActionExecutingContext context)
    {
        if (context.HttpContext is not { } httpContext)
        {
            return;
        }

        var email = ExtractEmailFromActionArguments(context, _emailArgumentName);
        if (string.IsNullOrWhiteSpace(email))
        {
            return;
        }

        var identifier = $"email:{email.Trim().ToLowerInvariant()}";
        var limiter = _useSlidingWindow
            ? httpContext.CreateSlidingLimiterForIdentifier(identifier)
            : httpContext.CreateFixedLimiterForIdentifier(identifier);

        using var lease = limiter.AttemptAcquire(1);
        if (!lease.IsAcquired)
        {
            context.Result = new StatusCodeResult(StatusCodes.Status429TooManyRequests);
        }
    }

    public void OnActionExecuted(ActionExecutedContext context)
    {
        // no-op
    }

    private static string? ExtractEmailFromActionArguments(ActionExecutingContext context, string emailArgumentName)
    {
        foreach (var kvp in context.ActionArguments)
        {
            if (kvp.Value is null)
            {
                continue;
            }

            if (kvp.Value is string str && string.Equals(kvp.Key, emailArgumentName, StringComparison.OrdinalIgnoreCase))
            {
                return str;
            }

            var prop = kvp.Value.GetType().GetProperty(emailArgumentName, System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.IgnoreCase);
            if (prop is not null && prop.PropertyType == typeof(string))
            {
                var val = prop.GetValue(kvp.Value) as string;
                if (!string.IsNullOrWhiteSpace(val))
                {
                    return val;
                }
            }
        }

        return null;
    }
}


