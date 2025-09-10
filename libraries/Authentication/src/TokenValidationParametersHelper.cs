using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace AuthSample.Authentication;

public sealed class TokenValidationParametersHelper
{
    private readonly IOptions<AuthOptions> _options;
    private readonly ConfigurationManager<OpenIdConnectConfiguration> _configurationManager;

    public TokenValidationParametersHelper(IOptions<AuthOptions> options)
    {
        _options = options;

        var authority = _options.Value.Authority?.TrimEnd('/') ?? string.Empty;
        if (string.IsNullOrEmpty(authority))
        {
            throw new InvalidOperationException("Authority is not configured. Check your Authentication configuration section.");
        }

        var metadataAddress = $"{authority}/.well-known/openid-configuration";

        var httpRetriever = new HttpDocumentRetriever
        {
            RequireHttps = true
        };

        _configurationManager = new ConfigurationManager<OpenIdConnectConfiguration>(
            metadataAddress,
            new OpenIdConnectConfigurationRetriever(),
            httpRetriever
        )
        {
            // Cache metadata/JWKS; adjust as needed for your rotation cadence
            AutomaticRefreshInterval = TimeSpan.FromHours(12),
            RefreshInterval = TimeSpan.FromHours(1)
        };
    }

    public async Task<TokenValidationParameters> GetTokenValidationParameters(CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(_options.Value.Audience))
        {
            throw new InvalidOperationException($"Audience is not configured. Check your Authentication configuration section. Authority: {_options.Value.Authority}");
        }

        var discoveryDocument = await _configurationManager.GetConfigurationAsync(ct).ConfigureAwait(false);

        return new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKeys = discoveryDocument.SigningKeys,

            ValidateIssuer = true,
            // Prefer the discovered issuer to avoid subtle mismatches
            ValidIssuer = discoveryDocument.Issuer,

            ValidateAudience = false,

            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(60)
        };
    }
}
