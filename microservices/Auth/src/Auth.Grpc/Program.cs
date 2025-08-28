using Amazon.CognitoIdentityProvider;
using AuthSample.Api.Cors;
using AuthSample.Api.Exceptions;
using AuthSample.Api.Secrets;
using AuthSample.Auth.Core;
using AuthSample.Auth.Grpc.Services;
using AuthSample.Auth.Infrastructure.Cognito;
using AuthSample.Authentication;
using AuthSample.Infrastructure;
using AuthSample.Logging;
using AuthSample.Api.Validation;
using FluentValidation;

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

// Add CORS policy
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddAuthSampleCors(options => builder.Configuration.GetSection("Cors").Bind(options));
}

// Add authentication and authorization
builder.Services.AddAuthnAuthz(options => builder.Configuration.GetSection("Authentication").Bind(options));

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
    app.MapGrpcService<SignUpManagerService>()
        .EnableGrpcWeb()
        .RequireCors();
}
else
{
    app.MapGrpcService<GreeterService>();
    app.MapGrpcService<SignUpManagerService>();
}


app.MapHealthChecks("/health");

app.Run();
