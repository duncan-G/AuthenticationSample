namespace AuthSample.Api.Cors;

public record CorsOptions
{
    public IReadOnlyCollection<string> AllowedOrigins { get; init; } = [];
}
