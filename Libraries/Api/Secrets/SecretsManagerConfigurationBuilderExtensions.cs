using Microsoft.Extensions.Configuration;

namespace AuthenticationSample.Api.Secrets;

/// <summary>
///     Extension method to wire the provider into any IConfigurationBuilder.
/// </summary>
public static class SecretsManagerConfigurationBuilderExtensions
{
    /// <param name="builder">Configuration builder</param>
    /// <param name="secretId">Secret name or full ARN.</param>
    /// <param name="prefix">Secret prefix.</param>
    /// <param name="reloadAfter">
    ///     Optional: if set, the provider polls at this interval and hot‑reloads the configuration.
    /// </param>
    public static IConfigurationBuilder AddSecretsManager(
        this IConfigurationBuilder builder,
        string secretId,
        string? prefix,
        TimeSpan? reloadAfter = null)
    {
        var source = new SecretsManagerConfigurationSource(secretId, prefix, reloadAfter);
        builder.Add(source);
        return builder;
    }
}
