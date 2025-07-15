using System.Text.Json;
using Amazon;
using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

/// <summary>
///     Describes a single AWS Secrets Manager secret to IConfiguration.
/// </summary>
public sealed class SecretsManagerConfigurationSource(
    string secretId,
    RegionEndpoint region,
    TimeSpan? reloadAfter)
    : IConfigurationSource
{
    public string SecretId { get; } = secretId ?? throw new ArgumentNullException(nameof(secretId));
    public RegionEndpoint Region { get; } = region ?? throw new ArgumentNullException(nameof(region));
    public TimeSpan? ReloadAfter { get; } = reloadAfter;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new SecretsManagerConfigurationProvider(this);
    }
}

/// <summary>
///     Pulls key/value pairs from the secret and (optionally) hot‑reloads.
/// </summary>
internal sealed class SecretsManagerConfigurationProvider
    : ConfigurationProvider, IDisposable
{
    private readonly IAmazonSecretsManager _client;
    private readonly SecretsManagerConfigurationSource _source;
    private Timer? _reloadTimer;

    public SecretsManagerConfigurationProvider(SecretsManagerConfigurationSource source)
    {
        _source = source;
        _client = new AmazonSecretsManagerClient(_source.Region);
    }

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
        var resp = await _client.GetSecretValueAsync(new GetSecretValueRequest { SecretId = _source.SecretId })
            .ConfigureAwait(false);

        var parsed = JsonSerializer.Deserialize<IDictionary<string, string?>>(resp.SecretString!)
                     ?? new Dictionary<string, string?>();

        // Replace Data so IConfiguration sees fresh values
        Data = new Dictionary<string, string?>(parsed, StringComparer.OrdinalIgnoreCase);
        OnReload();

        // Schedule future reloads (if requested) only once
        if (_source.ReloadAfter is { } interval && _reloadTimer is null)
        {
            _reloadTimer = new Timer(_ => Load(), null, interval, interval);
        }
    }
}

/// <summary>
///     Extension method to wire the provider into any IConfigurationBuilder.
/// </summary>
public static class SecretsManagerConfigurationBuilderExtensions
{
    /// <param name="builder">Confirugration builder</param>
    /// <param name="secretId">Secret name or full ARN.</param>
    /// <param name="region">AWS region containing the secret.</param>
    /// <param name="reloadAfter">
    ///     Optional: if set, the provider polls at this interval and hot‑reloads the configuration.
    /// </param>
    public static IConfigurationBuilder AddSecretsManager(
        this IConfigurationBuilder builder,
        string secretId,
        RegionEndpoint region,
        TimeSpan? reloadAfter = null)
    {
        ArgumentNullException.ThrowIfNull(builder);

        var source = new SecretsManagerConfigurationSource(secretId, region, reloadAfter);
        builder.Add(source);
        return builder;
    }
}
