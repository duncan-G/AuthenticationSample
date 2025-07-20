using System.Collections.Frozen;
using System.Text.Json;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

internal sealed class SecretsManagerConfigurationProvider(SecretsManagerConfigurationSource source)
    : ConfigurationProvider, IDisposable
{
    private const string SharedPrefix = "Shared_";
    private const string SharedOverridePrefix = "SharedOverride_";
    private const string OverridePrefix = "Override_";

    private readonly CancellationTokenSource _cancellation = new();

    private readonly Lazy<IAmazonSecretsManager> _client =
        new(() => new AmazonSecretsManagerClient(source.AwsOptions.Credentials, source.AwsOptions.Region));

    private PeriodicTimer? _reloadTimer;

    public void Dispose()
    {
        _cancellation.Cancel();
        _reloadTimer?.Dispose();
        if (_client.IsValueCreated)
        {
            _client.Value.Dispose();
        }
    }

    public override void Load()
    {
        LoadAsync().GetAwaiter().GetResult();
    }

    private async Task LoadAsync()
    {
        var secretId = source.SecretManagerOptions.SecretId;
        var secretJson = (await _client.Value.GetSecretValueAsync(
                new GetSecretValueRequest { SecretId = secretId }, _cancellation.Token).ConfigureAwait(false))
            .SecretString ?? "{}";

        var entries = JsonSerializer.Deserialize<Dictionary<string, string?>>(secretJson) ??
                      new Dictionary<string, string?>();
        var scopedEntries = ApplyScoping(entries, source.SecretManagerOptions);

        Data = scopedEntries;

        OnReload();
        StartReloadTimerOnce();
    }

    private static FrozenDictionary<string, string?> ApplyScoping(
        IReadOnlyDictionary<string, string?> entries, SecretsManagerOptions options)
    {
        var appPrefix = options.Prefix;
        var appOverridePrefix    = appPrefix is null
            ? null
            : $"{(appPrefix.EndsWith('_') ? appPrefix[..^1] : appPrefix)}{OverridePrefix}";

        var resolved = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        foreach (var (rawKey, secret) in entries)
        {
            if (string.IsNullOrEmpty(secret))
            {
                continue;
            }

            if (options.UseDevOverrides &&
                (TryStripAndReplace(rawKey, SharedOverridePrefix, out var overrideKey) ||
                 TryStripAndReplace(rawKey, appOverridePrefix, out overrideKey)))
            {
                resolved[overrideKey] = secret;
                continue;
            }

            if (TryStripAndReplace(rawKey, SharedPrefix, out var key) ||
                TryStripAndReplace(rawKey, appPrefix, out key))
            {
                resolved.TryAdd(key, secret); // TryAdd so it can be ignored if override key is already present
            }
        }

        return resolved.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
    }

    private void StartReloadTimerOnce()
    {
        if (_reloadTimer is not null || source.SecretManagerOptions.ReloadAfter is not { } interval)
        {
            return;
        }

        _reloadTimer = new PeriodicTimer(interval);
        _ = Task.Run(async () =>
        {
            while (await _reloadTimer.WaitForNextTickAsync(_cancellation.Token).ConfigureAwait(false))
            {
                try
                {
                    await LoadAsync().ConfigureAwait(false);
                }
                catch when (_cancellation.IsCancellationRequested)
                {
                }
                catch
                {
                    /* swallow or log; loop continues */
                }
            }
        });
    }

    private static bool TryStripAndReplace(string rawKey, string? prefix, out string key)
    {
        if (prefix != null && rawKey.StartsWith(prefix, StringComparison.Ordinal))
        {
            key = rawKey[prefix.Length..].Replace("__", ":", StringComparison.Ordinal);
            return true;
        }

        key = null!;
        return false;
    }
}
