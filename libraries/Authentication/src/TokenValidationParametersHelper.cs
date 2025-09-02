using AuthSample.Authentication;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace AuthSample.Auth.Grpc;

public sealed class TokenValidationParametersHelper(IOptions<AuthOptions> options)
{
    public async Task<TokenValidationParameters> GetTokenValidationParameters(CancellationToken ct = default)
    {
        var authority = options.Value.Authority.TrimEnd('/');
        var metadataAddress = $"{authority}/.well-known/openid-configuration";

        var httpRetriever = new HttpDocumentRetriever
        {
            RequireHttps = true
        };

        var configurationManager =
            new ConfigurationManager<OpenIdConnectConfiguration>(
                metadataAddress,
                new OpenIdConnectConfigurationRetriever(),
                httpRetriever
            );

        var discoveryDocument = await configurationManager.GetConfigurationAsync(ct).ConfigureAwait(false);

        return new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = discoveryDocument.SigningKeys,

            ValidateIssuer = true,
            // Prefer the discovered issuer to avoid subtle mismatches
            ValidIssuer = discoveryDocument.Issuer,

            ValidateAudience = true,
            ValidAudience = options.Value.Audience,

            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(60)
        };
    }
}
