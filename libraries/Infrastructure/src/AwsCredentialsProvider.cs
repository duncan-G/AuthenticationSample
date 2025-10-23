using System.Diagnostics;
using Amazon.Runtime;
using Amazon.Runtime.CredentialManagement;

namespace AuthSample.Infrastructure;

/// <summary>
///     Provides AWS credentials for application infrastructure services
/// </summary>
internal static class AwsCredentialsProvider
{
    /// <summary>
    ///     Loads AWS SSO credentials using the specified profile
    /// </summary>
    /// <returns>AWS SSO credentials</returns>
    public static AWSCredentials LoadSsoCredentials(
        string ssoProfile,
        string ssoClient)
    {
        var chain = new CredentialProfileStoreChain();
        if (!chain.TryGetAWSCredentials(ssoProfile, out var credentials))
        {
            throw new InvalidOperationException("Unable to get AWS profile");
        }

        var ssoCredentials = credentials as SSOAWSCredentials;

        if (ssoCredentials == null)
        {
            throw new InvalidOperationException("The specified AWS profile is not configured for SSO.");
        }

        ssoCredentials.Options.ClientName = ssoClient;
        return ssoCredentials;
    }
}
