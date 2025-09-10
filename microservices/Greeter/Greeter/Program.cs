using AuthSample.Api.Exceptions;
using AuthSample.Api.RateLimiting;
using AuthSample.Api.Secrets;
using AuthSample.Api.Validation;
using AuthSample.Authentication;
using AuthSample.Greeter.Services;
using AuthSample.Infrastructure;
using AuthSample.Logging;
using FluentValidation;

var builder = WebApplication.CreateBuilder(args);

// Configure AWS options from environment variables
var awsOptions = builder.AddAwsOptions("AuthSample-GreeterService");

builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddSecretsManager(
        awsOptions,
        options => builder.Configuration.Bind("Secrets", options));;

// Configure logging
builder.AddLogging(options => builder.Configuration.Bind("ApplicationLogging", options));

// Configure rate limiting
builder.Services.AddRedisRateLimiter(options => builder.Configuration.Bind("Redis", options));

// Add services to container
builder.Services.AddGrpc();builder.Services.AddGrpc(options =>
{
    options.Interceptors.Add<ValidationInterceptor>();
    options.Interceptors.Add<ExceptionsInterceptor>();
});
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// Add authentication and authorization
builder.Services.AddAuthnAuthz(options => builder.Configuration.Bind("Authentication", options));

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

app.MapGrpcService<GreeterService>();
app.MapHealthChecks("/health");

app.Run();

app.UseAuthentication();
app.UseAuthorization();

// Configure the HTTP request pipeline.
app.MapGrpcService<GreeterService>();

app.MapHealthChecks("/health");

app.Run();
