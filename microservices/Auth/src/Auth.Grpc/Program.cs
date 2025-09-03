using Amazon.CognitoIdentityProvider;
using AuthSample.Api.Exceptions;
using AuthSample.Api.RateLimiting;
using AuthSample.Api.Secrets;
using AuthSample.Auth.Core;
using AuthSample.Auth.Grpc.Services;
using AuthSample.Auth.Infrastructure.Cognito;
using AuthSample.Authentication;
using AuthSample.Infrastructure;
using AuthSample.Logging;
using AuthSample.Api.Validation;
using AuthSample.Auth.Core.Identity;
using FluentValidation;
using StackExchange.Redis;

var builder = WebApplication.CreateBuilder(args);

// Configure AWS options from environment variables
var awsOptions = builder.AddAwsOptions("AuthSample-AuthService");

builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddSecretsManager(
        awsOptions,
        options => builder.Configuration.Bind("Secrets", options));

// Configure logging
builder.AddLogging(options => builder.Configuration.Bind("ApplicationLogging", options));

// Configure cache
builder.Services.AddRedisRateLimiter(options => builder.Configuration.Bind("Redis", options));
builder.Services.AddStackExchangeRedisCache(options => builder.Configuration.Bind("Redis", options));

// Add services to the container.
builder.Services.AddGrpc(options =>
{
    options.Interceptors.Add<ValidationInterceptor>();
    options.Interceptors.Add<ExceptionsInterceptor>();
});
builder.Services.Configure<CognitoOptions>(builder.Configuration.GetSection("Cognito"));
builder.Services.AddAWSService<IAmazonCognitoIdentityProvider>();
builder.Services.AddScoped<IIdentityGateway, CognitoIdentityGateway>();
builder.Services.AddScoped<IIdentityService, IdentityService>();
builder.Services.AddValidatorsFromAssemblyContaining<Program>();

// Add authentication and authorization
builder.Services.AddAuthnAuthz(options => builder.Configuration.Bind("Authentication", options));

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Capture AWS SDK logs
app.Services.GetRequiredService<ILoggerFactory>()
    .ConfigureAWSSDKLogging();

// Configure the HTTP request pipeline.
app.MapGrpcService<GreeterService>();
app.MapGrpcService<SignUpService>();
app.MapGrpcService<AuthorizationService>();

app.MapHealthChecks("/health");

app.Run();
