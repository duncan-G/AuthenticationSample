using System.Threading.RateLimiting;
using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

internal sealed class RedisScriptRateLimiter(
    IDatabase database,
    LuaScript script,
    string key,
    int windowSeconds,
    int maxRequests)
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
        var result = (int)database.ScriptEvaluate(script, new
        {
            key = (RedisKey)key,
            window = windowSeconds,
            max_requests = maxRequests
        });
        return result == 0;
    }

    private async Task<bool> EvaluateScriptAsync(CancellationToken cancellationToken)
    {
        var task = database.ScriptEvaluateAsync(script, new
        {
            key = (RedisKey)key,
            window = windowSeconds,
            max_requests = maxRequests
        });
        var result = (int)await task.ConfigureAwait(false);
        return result == 0;
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


