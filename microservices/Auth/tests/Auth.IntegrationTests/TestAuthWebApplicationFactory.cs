using System.Text.Encodings.Web;
using AuthSample.Auth.Core.Identity;
using Grpc.Net.Client;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Options;
using Moq;
using StackExchange.Redis;
using Microsoft.AspNetCore.TestHost;

namespace AuthSample.Auth.IntegrationTests;

public sealed class TestAuthWebApplicationFactory : WebApplicationFactory<Program>
{
    static TestAuthWebApplicationFactory()
    {
        // Ensure Program.cs can read these before the host is constructed
        Environment.SetEnvironmentVariable("AWS_REGION", "us-west-1");
        Environment.SetEnvironmentVariable("AWS_PROFILE", "default");
    }
    public Mock<IIdentityService> IdentityServiceMock { get; } = new();
    public Mock<ISignUpEligibilityGuard> EligibilityGuardMock { get; } = new();
    public Mock<ILogger<Grpc.Services.SignUpService>> LoggerMock { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureTestServices(services =>
        {
            // Ensure required env vars (in case Program reads them during service setup)
            Environment.SetEnvironmentVariable("AWS_REGION", "us-east-1");
            Environment.SetEnvironmentVariable("AWS_PROFILE", "default");

            // Replace infrastructure dependencies with test doubles
            services.AddSingleton<ISignUpEligibilityGuard>(_ => EligibilityGuardMock.Object);
            services.AddScoped<IIdentityService>(_ => IdentityServiceMock.Object);
            services.AddSingleton<ILogger<Grpc.Services.SignUpService>>(_ => LoggerMock.Object);

            // Add test authentication scheme
            services.AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = "Test";
                    options.DefaultChallengeScheme = "Test";
                })
                .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });

            // Add simple authorization defaults/policies for tests
            services.AddAuthorization(options =>
            {
                options.FallbackPolicy = new AuthorizationPolicyBuilder()
                    .RequireAuthenticatedUser()
                    .Build();
                options.AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"));
            });

            // Provide a fake Redis connection that always allows rate limit checks
            var redisDbMock = new Mock<IDatabase>();
            redisDbMock
                .Setup(db => db.ScriptEvaluate(It.IsAny<LuaScript>(), It.IsAny<object?>(), It.IsAny<CommandFlags>()))
                .Returns(RedisResult.Create([0, 0]));
            redisDbMock
                .Setup(db => db.ScriptEvaluateAsync(It.IsAny<LuaScript>(), It.IsAny<object?>(), It.IsAny<CommandFlags>()))
                .ReturnsAsync(RedisResult.Create([0, 0]));

            var muxMock = new Mock<IConnectionMultiplexer>();
            muxMock.Setup(m => m.GetDatabase(It.IsAny<int>(), It.IsAny<object?>()))
                .Returns(redisDbMock.Object);
            services.AddSingleton<IConnectionMultiplexer>(_ => muxMock.Object);
        });
    }

    private sealed class TestAuthHandler(
        IOptionsMonitor<AuthenticationSchemeOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder)
        : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var role = Request.Headers["x-test-role"].ToString();
            var userId = Request.Headers["x-test-user"].ToString();

            var claims = new List<System.Security.Claims.Claim>
            {
                new("sub", string.IsNullOrWhiteSpace(userId) ? "test-user" : userId),
            };
            if (!string.IsNullOrWhiteSpace(role))
            {
                claims.Add(new System.Security.Claims.Claim(System.Security.Claims.ClaimTypes.Role, role));
            }

            var identity = new System.Security.Claims.ClaimsIdentity(claims, Scheme.Name);
            var principal = new System.Security.Claims.ClaimsPrincipal(identity);
            var ticket = new AuthenticationTicket(principal, Scheme.Name);
            return Task.FromResult(AuthenticateResult.Success(ticket));
        }
    }

    public GrpcChannel CreateGrpcChannel()
    {
        // Ensure the server is created and use its handler-backed HttpClient
        var httpClient = CreateDefaultClient();
        return GrpcChannel.ForAddress(httpClient.BaseAddress ?? new Uri("http://localhost"), new GrpcChannelOptions
        {
            HttpClient = httpClient
        });
    }
}


