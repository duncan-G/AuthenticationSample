using System.Collections.Frozen;
using System.Text.Json;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

/// <summary>
/// Exposes values from an AWS Secrets Manager JSON secret as
/// <see cref="IConfiguration"/> keys.
///
/// • Includes keys that start with <c>Shared_</c> or the configured <c>Prefix</c>.
/// • Optional: keys with <c>Override_</c> replace earlier values.
/// • Converts double‑underscores (<c>__</c>) to colons (<c>:</c>).
/// • Supports periodic reload via <c>ReloadAfter</c>.
/// </summary>
internal sealed class SecretsManagerConfigurationProvider(SecretsManagerConfigurationSource source)
    : ConfigurationProvider, IDisposable
{
    private const string SharedPrefix = "Shared_";
    private const string OverrideTag = "Override_";

    private readonly Lazy<IAmazonSecretsManager> _client =
        new(() => new AmazonSecretsManagerClient(
            source.AwsOptions.Credentials, source.AwsOptions.Region));

    private readonly CancellationTokenSource _cts = new();
    private PeriodicTimer? _reloadTimer;

    public void Dispose()
    {
        _reloadTimer?.Dispose();
        _cts.Cancel();
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
        var sm = _client.Value;

        var resp = await sm.GetSecretValueAsync(
            new GetSecretValueRequest { SecretId = source.SecretManagerOptions.SecretId },
            _cts.Token).ConfigureAwait(false);

        var raw = JsonSerializer.Deserialize<Dictionary<string, string?>>(resp.SecretString!)
                  ?? new Dictionary<string, string?>();

        var keys = BuildKeySet(raw, source.SecretManagerOptions);

        // convert "__" → ":" (only at leaf level)
        Data = keys.ToDictionary(
            kvp => kvp.Key.Replace("__", ":", StringComparison.Ordinal),
            kvp => kvp.Value,
            StringComparer.OrdinalIgnoreCase);

        OnReload();

        // one‑time timer wiring
        if (source.SecretManagerOptions.ReloadAfter is { } interval && _reloadTimer is null)
        {
            _reloadTimer = new PeriodicTimer(interval);
            _ = Task.Run(KeepReloadingAsync);
        }
    }

    private async Task KeepReloadingAsync()
    {
        while (await _reloadTimer!.WaitForNextTickAsync(_cts.Token).ConfigureAwait(false))
        {
            try
            {
                await LoadAsync().ConfigureAwait(false);
            }
            catch when (_cts.IsCancellationRequested)
            {
                /* shutting down */
            }
            catch
            {
                /* swallow or log; keep timer alive */
            }
        }
    }

    private static FrozenDictionary<string, string?> BuildKeySet(
        IReadOnlyDictionary<string, string?> all,
        SecretsManagerOptions opt)
    {
        var wanted = opt.Prefix;
        var useDevOv = opt.UseDevOverrides;

        var result = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        foreach (var (key, value) in all)
        {
            // 1. shared keys
            if (key.StartsWith(SharedPrefix, StringComparison.Ordinal))
            {
                result[key[SharedPrefix.Length..]] = value;
            }

            // 2. scoped keys
            else if (wanted is { Length: > 0 } &&
                     key.StartsWith(wanted, StringComparison.Ordinal))
            {
                result[key[wanted.Length..]] = value;
            }

            // 3. overrides (optional)
            if (useDevOv && IsOverride(key, SharedPrefix) && key.Length > SharedPrefix.Length)
            {
                result[key[(SharedPrefix + OverrideTag).Length..]] = value;
            }

            if (useDevOv && wanted is { Length: > 0 } && IsOverride(key, wanted))
            {
                result[key[(wanted.TrimEnd('_') + "_" + OverrideTag).Length..]] = value;
            }
        }

        return result.ToFrozenDictionary(StringComparer.OrdinalIgnoreCase);
    }

    private static bool IsOverride(string key, string prefix)
    {
        return key.StartsWith(prefix, StringComparison.Ordinal)
               && key.AsSpan(prefix.Length).StartsWith(OverrideTag.AsSpan(), StringComparison.Ordinal);
    }
}
