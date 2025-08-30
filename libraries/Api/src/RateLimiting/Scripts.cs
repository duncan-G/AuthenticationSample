using StackExchange.Redis;

namespace AuthSample.Api.RateLimiting;

public static class Scripts
{
    public static LuaScript SlidingWindowScript => LuaScript.Prepare(SlidingWindowLua);

    public static LuaScript FixedWindowScript => LuaScript.Prepare(FixedWindowLua);

    private const string SlidingWindowLua = @"
            local current_time = redis.call('TIME')
            local trim_time = tonumber(current_time[1]) - @window
            redis.call('ZREMRANGEBYSCORE', @key, 0, trim_time)
            local request_count = redis.call('ZCARD', @key)

            if request_count < tonumber(@max_requests) then
                redis.call('ZADD', @key, current_time[1], current_time[1] .. current_time[2])
                redis.call('EXPIRE', @key, @window)
                return 0
            end
            return 1
        ";

    private const string FixedWindowLua = @"
            local current_time = redis.call('TIME')
            local window_start = math.floor(tonumber(current_time[1]) / @window) * @window
            local window_key = @key .. ':' .. tostring(window_start)

            local count = redis.call('INCR', window_key)
            if count == 1 then
                redis.call('EXPIRE', window_key, @window)
            end

            if count <= tonumber(@max_requests) then
                return 0
            end
            return 1
        ";
}


