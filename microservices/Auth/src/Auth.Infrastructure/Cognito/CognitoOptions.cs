namespace AuthSample.Auth.Infrastructure.Cognito;

public class CognitoOptions
{
    public string UserPoolId { get; set; } = null!;
    public string ClientId { get; set; } = null!;
    public string Secret { get; set; } = null!;
}
