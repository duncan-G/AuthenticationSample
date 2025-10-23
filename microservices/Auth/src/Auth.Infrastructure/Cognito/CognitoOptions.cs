namespace AuthSample.Auth.Infrastructure.Cognito;

public class CognitoOptions
{
    public required string UserPoolId { get; set; }
    public required string ClientId { get; set; }
    public required string Secret { get; set; }

    public required int RefreshTokenExpirationDays { get; set; }

    public string? ConfirmedUserSeedScriptPath { get; set; }
}
