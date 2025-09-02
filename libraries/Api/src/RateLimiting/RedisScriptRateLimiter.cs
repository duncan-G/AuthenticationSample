using System.Diagnostics;
using System.Threading.RateLimiting;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

internal sealed class RedisScriptRateLimiter(
    IDatabase database,
    LuaScript script,
    string key,
    int windowSeconds,
    int maxRequests,
    string algorithm)
    : RateLimiter
{
    public override TimeSpan? IdleDuration => null;

    protected override async ValueTask<RateLimitLease> AcquireAsyncCore(int permitCount, CancellationToken cancellationToken)
    {
        var allowed = await EvaluateScriptAsync(cancellationToken).ConfigureAwait(false);
        return new SimpleLease(allowed);
    }

    public override RateLimiterStatistics? GetStatistics() => null;

    protected override RateLimitLease AttemptAcquireCore(int permitCount)
    {
        var allowed = EvaluateScriptSync();
        return new SimpleLease(allowed);
    }

    protected override void Dispose(bool disposing)
    {
        // no-op
    }

    private bool EvaluateScriptSync()
    {
        var activity = Activity.Current;
        activity?.SetTag("rate.limit.key", key);
        activity?.SetTag("rate.limit.window_seconds", windowSeconds);
        activity?.SetTag("rate.limit.max_requests", maxRequests);
        activity?.SetTag("rate.limit.algorithm", algorithm);

        var result = (int)database.ScriptEvaluate(script, new
        {
            key = (RedisKey)key,
            window = windowSeconds,
            max_requests = maxRequests
        });
        var allowed = result == 0;
        activity?.SetTag("rate.limit.allowed", allowed);
        if (!allowed)
        {
            activity?.AddEvent(new ActivityEvent("rate_limit.blocked"));
        }
        return allowed;
    }

    private async Task<bool> EvaluateScriptAsync(CancellationToken cancellationToken)
    {
        var activity = Activity.Current;
        activity?.SetTag("rate.limit.key", key);
        activity?.SetTag("rate.limit.window_seconds", windowSeconds);
        activity?.SetTag("rate.limit.max_requests", maxRequests);
        activity?.SetTag("rate.limit.algorithm", algorithm);

        var task = database.ScriptEvaluateAsync(script, new
        {
            key = (RedisKey)key,
            window = windowSeconds,
            max_requests = maxRequests
        });
        var result = (int)await task.ConfigureAwait(false);
        var allowed = result == 0;
        activity?.SetTag("rate.limit.allowed", allowed);
        if (!allowed)
        {
            activity?.AddEvent(new ActivityEvent("rate_limit.blocked"));
        }
        return allowed;
    }

    private sealed class SimpleLease(bool isAcquired) : RateLimitLease
    {
        public override bool IsAcquired => isAcquired;

        public override IEnumerable<string> MetadataNames => [];

        public override bool TryGetMetadata(string metadataName, out object? metadata)
        {
            metadata = null;
            return false;
        }
    }
}


