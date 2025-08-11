using System.Diagnostics;
using Amazon.Extensions.NETCore.Setup;
using Amazon.Runtime;
using Amazon.Runtime.CredentialManagement;

namespace AuthenticationSample.Infrastructure;

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

        ssoCredentials!.Options.ClientName = ssoClient;
        ssoCredentials.Options.SsoVerificationCallback = args =>
        {
            // Launch a browser window that prompts the SSO user to complete an SSO sign-in.
            // This method is only invoked if the session doesn't already have a valid SSO token.
            // NOTE: Process.Start might not support launching a browser on macOS or Linux. If not,
            //       use an appropriate mechanism on those systems instead.
            Process.Start(new ProcessStartInfo { FileName = args.VerificationUriComplete, UseShellExecute = true });
        };

        return ssoCredentials;
    }
}
