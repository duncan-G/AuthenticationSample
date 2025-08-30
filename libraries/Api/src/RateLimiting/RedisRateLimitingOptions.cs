namespace AuthSample.Api.RateLimiting;

public sealed class RedisRateLimitingOptions
{
    public string Configuration { get; set; } = "localhost:6379";
    public int SlidingWindowSeconds { get; set; } = 30;
    public int SlidingMaxRequests { get; set; } = 10;
    public int FixedWindowSeconds { get; set; } = 60;
    public int FixedMaxRequests { get; set; } = 60;
}
