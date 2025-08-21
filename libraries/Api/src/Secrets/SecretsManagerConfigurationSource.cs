using Amazon.Extensions.NETCore.Setup;
using Microsoft.Extensions.Configuration;

namespace AuthSample.Api.Secrets;

internal sealed class SecretsManagerConfigurationSource(
    AWSOptions awsOptions,
    SecretsManagerOptions secretManagerOptions)
    : IConfigurationSource
{
    public AWSOptions AwsOptions => awsOptions;

    public SecretsManagerOptions SecretManagerOptions => secretManagerOptions;

    public IConfigurationProvider Build(IConfigurationBuilder builder)
    {
        return new SecretsManagerConfigurationProvider(this);
    }
}
