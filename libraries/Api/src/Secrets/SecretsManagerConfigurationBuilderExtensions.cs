using Amazon.Extensions.NETCore.Setup;
using Microsoft.Extensions.Configuration;

namespace AuthSample.Api.Secrets;

/// <summary>
///     Extension method to wire the provider into any IConfigurationBuilder.
/// </summary>
public static class SecretsManagerConfigurationBuilderExtensions
{
    public static IConfigurationBuilder AddSecretsManager(
        this IConfigurationBuilder builder,
        AWSOptions awsOptions,
        Action<SecretsManagerOptions> configureSecretManagerOptions)
    {
        var secretManagerOptions = new SecretsManagerOptions();
        configureSecretManagerOptions(secretManagerOptions);
        if (string.IsNullOrEmpty(secretManagerOptions.SecretId))
        {
            throw new InvalidOperationException("SecretId cannot be null or empty.");
        }

        var source = new SecretsManagerConfigurationSource(awsOptions, secretManagerOptions);
        builder.Add(source);
        return builder;
    }
}
