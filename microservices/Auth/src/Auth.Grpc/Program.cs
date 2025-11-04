using Amazon.CognitoIdentityProvider;
using AuthSample.Api.Exceptions;
using AuthSample.Api.RateLimiting;
using AuthSample.Api.Secrets;
using AuthSample.Auth.Grpc.Services;
using AuthSample.Auth.Grpc.Services.Internal;
using AuthSample.Auth.Infrastructure.DynamoDB;
using AuthSample.Auth.Infrastructure.Cognito;
using AuthSample.Auth.Core.Identity;
using AuthSample.Authentication;
using AuthSample.Infrastructure;
using AuthSample.Logging;
using AuthSample.Api.Validation;
using AuthSample.Auth.Infrastructure.DynamoDb;
using FluentValidation;

var builder = WebApplication.CreateBuilder(args);

// Configure AWS options from environment variables
var awsOptions = builder.AddAwsOptions("AuthSample-AuthService");

builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddEnvironmentVariables("Shared_")
    .AddSecretsManager(
        builder.Environment,
        awsOptions,
        options => builder.Configuration.Bind("Secrets", options));

// Configure logging
builder.AddLogging(options => builder.Configuration.Bind("ApplicationLogging", options));

// Configure rate limiting
builder.Services.AddRedisRateLimiter(options => builder.Configuration.Bind("Redis", options));

// Add services to the container.
builder.Services.AddGrpc(options =>
{
    options.Interceptors.Add<ValidationInterceptor>();
    options.Interceptors.Add<ExceptionsInterceptor>();
});
builder.Services.Configure<CognitoOptions>(builder.Configuration.GetSection("Cognito"));
builder.Services.AddAWSService<IAmazonCognitoIdentityProvider>();
builder.Services.AddDynamoDb(builder.Environment, options => builder.Configuration.Bind("DynamoDb", options));
builder.Services.AddScoped<IIdentityGateway, CognitoIdentityGateway>();
builder.Services.AddScoped<IRefreshTokenStore, DynamoDbRefreshTokenStore>();
builder.Services.AddScoped<IIdentityService, IdentityService>();
builder.Services.AddSingleton<ISignUpEligibilityGuard, CognitoSignUpEligibilityGuard>();
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
app.MapGrpcService<SignUpService>();
app.MapGrpcService<AuthorizationService>();
app.MapGrpcService<InternalAuthorizationService>();

app.MapHealthChecks("/health");

app.Run();

// Make Program class accessible for testing
public partial class Program { }
