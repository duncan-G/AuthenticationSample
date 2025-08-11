using Amazon;
using Amazon.Extensions.NETCore.Setup;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace AuthenticationSample.Infrastructure;

/// <summary>
///     Extension methods for configuring AWS options
/// </summary>
public static class AwsOptionsExtensions
{
    /// <summary>
    ///     Adds AWS options from environment variables and configures credentials
    /// </summary>
    /// <param name="builder">The host application builder</param>
    /// <param name="ssoClientName">SSO client name</param>
    /// <returns>The configured AWS options</returns>
    public static AWSOptions AddAwsOptions(this IHostApplicationBuilder builder, string ssoClientName)
    {
        var awsRegion = Environment.GetEnvironmentVariable("AWS_REGION");
        var awsProfile = Environment.GetEnvironmentVariable("AWS_PROFILE");
        if (awsRegion == null)
        {
            throw new InvalidOperationException("AWS Region not found in environment.");
        }

        if (builder.Environment.IsDevelopment() && awsProfile == null)
        {
            throw new InvalidOperationException("AWS Profile not found in environment.");
        }

        var awsOptions = new AWSOptions
        {
            Region = RegionEndpoint.GetBySystemName(awsRegion),
            Profile = awsProfile
        };

        // AWS SDK will use another method to get credentials in production
        // because the service will be running in an EC2 Instance
        if (builder.Environment.IsDevelopment())
        {
            try
            {
                var credentials = AwsCredentialsProvider.LoadSsoCredentials(
                    awsProfile!,
                    ssoClientName
                );
                awsOptions.Credentials = credentials;
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to load AWS SSO credentials for profile '{awsOptions.Profile}'",
                    ex);
            }
        }

        builder.Services.AddDefaultAWSOptions(awsOptions);

        return awsOptions;
    }
}
