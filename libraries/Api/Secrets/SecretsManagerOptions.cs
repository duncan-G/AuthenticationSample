namespace AuthSample.Api.Secrets;

public sealed class SecretsManagerOptions
{
    public string SecretId { get; set; } = string.Empty;

    public bool UseDevOverrides { get; set; }

    public string? Prefix { get; set; }

    public TimeSpan? ReloadAfter { get; set; }
}
