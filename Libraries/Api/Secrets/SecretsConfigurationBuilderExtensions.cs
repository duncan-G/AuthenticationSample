using Amazon.SecretsManager;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AuthenticationSample.Api.Secrets;

public static class SecretsApplicationBuilderExtensions
{
    public static IHostApplicationBuilder AddSecrets(
        IHostApplicationBuilder builder, string serviceName, string secretName)
    {
        builder.Services.AddAWSService<IAmazonSecretsManager>();


        builder.Configuration.AddSecretsManager(opts =>
        {
            // Pull only the secrets that start with this prefix
            opts.SecretFilter = s => s.Name.StartsWith("prod/my-api/");

            // Turn key names like  ConnectionStrings__Default  →  ConnectionStrings:Default
            opts.KeyGenerator = (_, key) => key
                .Replace("prod/my-api/", string.Empty)
                .Replace("__", ":");

            // OPTIONAL: hot-reload every 5 minutes (handles rotations automatically)
            opts.PollingInterval = TimeSpan.FromMinutes(5);
        });
    }
}
