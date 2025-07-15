using System.Text.Json;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

/// <summary>
///     Pulls key/value pairs from the secret and (optionally) hot‑reloads.
/// </summary>
internal sealed class SecretsManagerConfigurationProvider(SecretsManagerConfigurationSource source)
    : ConfigurationProvider, IDisposable
{
    private const string SharedSecretPrefix = "Shared_";
    private readonly AmazonSecretsManagerClient _client = new();
    private Timer? _reloadTimer;

    public void Dispose()
    {
        _reloadTimer?.Dispose();
        _client.Dispose();
    }

    public override void Load()
    {
        LoadAsync().GetAwaiter().GetResult();
    }

    private async Task LoadAsync()
    {
        var resp = await _client.GetSecretValueAsync(new GetSecretValueRequest { SecretId = source.SecretId })
            .ConfigureAwait(false);

        var parsed = JsonSerializer.Deserialize<IDictionary<string, string?>>(resp.SecretString!)
                     ?? new Dictionary<string, string?>();

        // Replace Data so IConfiguration sees fresh values
        Data = new Dictionary<string, string?>(parsed, StringComparer.OrdinalIgnoreCase)
            .Where(kvp => (source.Prefix != null && kvp.Key.StartsWith(source.Prefix)) || kvp.Key.StartsWith(SharedSecretPrefix))
            .ToDictionary(kvp => kvp.Key, kvp => kvp.Value);

        OnReload();

        // Schedule future reloads (if requested) only once
        if (source.ReloadAfter is { } interval && _reloadTimer is null)
        {
            _reloadTimer = new Timer(_ => Load(), null, interval, interval);
        }
    }
}
