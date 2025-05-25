using AuthenticationSample.Api;
using AuthenticationSample.Authentication.Grpc.Services;
using AuthenticationSample.Api.Cors;
using AuthenticationSample.Logging;
using dotenv.net;

var builder = WebApplication.CreateBuilder(args);

// Load secrets into configuration
DotEnv.Load();
builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddEnvironmentVariables("Authentication:");

builder.ConfigureKestrel();

// Configure logging
builder.AddLogging(options =>
{
    options.ServiceName = "Authentication";
    options.AddAWSInstrumentation = true;
});

// Add mapping
builder.Services.AddAutoMapper(typeof(Program));

// Add services to the container.
builder.Services.AddGrpc();

// Add CORS policy
builder.Services.AddAuthenticationSampleCors(
    options => builder.Configuration.GetSection("Cors").Bind(options));

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Capture AWS SDK logs
app.Services.GetRequiredService<ILoggerFactory>()
    .ConfigureAWSSDKLogging();

// Configure the HTTP request pipeline.
app.UseCors(CorsExtensions.CorsPolicyName);
app.UseGrpcWeb();

app.MapGrpcService<GreeterService>()
    .EnableGrpcWeb()
    .RequireCors();

app.MapHealthChecks("/health");

app.Run();