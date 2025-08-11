namespace AuthenticationSample.Api.Cors;

public record CorsOptions
{
    public IReadOnlyCollection<string> AllowedOrigins { get; init; } = [];
}
