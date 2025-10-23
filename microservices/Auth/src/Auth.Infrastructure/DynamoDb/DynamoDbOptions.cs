namespace AuthSample.Auth.Infrastructure.DynamoDb;

public sealed class DynamoDbOptions
{
    public required string ServiceUrl { get; set; }

    public int TimeoutSeconds { get; set; }

    public int MaxErrorRetry { get; set; }
}
