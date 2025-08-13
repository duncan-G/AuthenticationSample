using AuthSample.Api.Cors;
using AuthSample.Api.Secrets;
using AuthSample.Auth.Grpc.Services;
using AuthSample.Infrastructure;
using AuthSample.Logging;

var builder = WebApplication.CreateBuilder(args);

// Configure AWS options from environment variables
var awsOptions = builder.AddAwsOptions("AuthSample-AuthService");

builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddEnvironmentVariables("Auth_")
    .AddSecretsManager(
        awsOptions,
        options => builder.Configuration.GetSection("Secrets").Bind(options));

// Configure logging
builder.AddLogging(options => builder.Configuration.GetSection("ApplicationLogging").Bind(options));

// Add services to the container.
builder.Services.AddGrpc();

// Add CORS policy
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddAuthSampleCors(options => builder.Configuration.GetSection("Cors").Bind(options));
}

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Capture AWS SDK logs
app.Services.GetRequiredService<ILoggerFactory>()
    .ConfigureAWSSDKLogging();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseGrpcWeb();
    app.UseCors(CorsExtensions.CorsPolicyName);
    app.MapGrpcService<GreeterService>()
        .EnableGrpcWeb()
        .RequireCors();
}
else
{
    app.MapGrpcService<GreeterService>();
}


app.MapHealthChecks("/health");

app.Run();
