using System.Diagnostics;
using Amazon.Extensions.NETCore.Setup;
using AuthSample.Auth.Core.Exceptions;
using AuthSample.Auth.Core.Identity;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using StackExchange.Redis;

namespace AuthSample.Auth.Infrastructure.Cognito;

public sealed class CognitoSignUpEligibilityGuard(
    IHostEnvironment environment,
    IOptions<AWSOptions> awsOptions,
    IOptions<CognitoOptions> cognitoOptions,
    IConnectionMultiplexer cache,
    ILogger<CognitoSignUpEligibilityGuard> logger) : ISignUpEligibilityGuard
{
    private static readonly ActivitySource ActivitySource = new("AuthSample.Auth.Infrastructure");
    private const string CacheKey = "cognito:confirmed_user_count";
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);
    private const int MaxConfirmedUsers = 2500;

    public async Task EnforceMaxConfirmedUsersAsync(CancellationToken cancellationToken = default)
    {
        if (!(await CanInitiateSignUpAsync(0,  cancellationToken).ConfigureAwait(false)))
        {
            throw new MaximumUsersReachedException();
        }
    }

    public async Task IncrementConfirmedUsersAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var db = cache.GetDatabase();
            if (await db.KeyExistsAsync(CacheKey).ConfigureAwait(false))
            {
                await db.StringIncrementAsync(CacheKey).ConfigureAwait(false);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to increment {CacheKey} in Redis; sign-up traffic may cause Cognito charges.", CacheKey);
        }
    }

    private void SeedConfirmedUsersCount()
    {
        if (!environment.IsDevelopment())
        {
            return;
        }

        var psi = new ProcessStartInfo
        {
            FileName = "/bin/bash",
            Arguments = cognitoOptions.Value.ConfirmedUserSeedScriptPath,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            Environment = { ["USER_POOL_ID"] = cognitoOptions.Value.UserPoolId }
        };

        if (!string.IsNullOrWhiteSpace(awsOptions.Value.Profile))
        {
            psi.Environment["AWS_PROFILE"] = awsOptions.Value.Profile;
        }

        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start preflight script process");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"get_confirmed_user_count.sh failed with exit code {process.ExitCode}: {stderr}");
        }

        var output = stdout.Trim();
        if (!int.TryParse(output, out var count) || count < 0)
        {
            throw new InvalidOperationException($"Invalid confirmed user count output: '{output}'");
        }

        var db = cache.GetDatabase();
        var ok = db.StringSet(CacheKey, count.ToString(), CacheTtl);
        if (!ok)
        {
            throw new InvalidOperationException("Failed to cache confirmed user count in Redis");
        }
    }

    private async Task<bool> CanInitiateSignUpAsync(int attempts = 0, CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoSignUpEligibilityGuard)}.{nameof(CanInitiateSignUpAsync)}");

        var db = cache.GetDatabase();
        try
        {
            var cached = await db.StringGetAsync(CacheKey).ConfigureAwait(false);
            if (cached.HasValue && int.TryParse(cached.ToString(), out var cachedCount))
            {
                return cachedCount <= MaxConfirmedUsers;
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to read {CacheKey} from Redis; denying sign-up to prevent unexpected costs.", CacheKey);
            throw;
        }

        if (attempts > 0)
        {
            return false;
        }

        SeedConfirmedUsersCount();
        return await CanInitiateSignUpAsync(attempts + 1, cancellationToken).ConfigureAwait(false);
    }

}


