using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

internal sealed class SecretsManagerConfigurationSource(
    string secretId,
    string? prefix,
    TimeSpan? reloadAfter)
    : IConfigurationSource
{
    public string SecretId { get; } = secretId ?? throw new ArgumentNullException(nameof(secretId));

    public string? Prefix { get; } = prefix;

    public TimeSpan? ReloadAfter { get; } = reloadAfter;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new SecretsManagerConfigurationProvider(this);
    }
}
