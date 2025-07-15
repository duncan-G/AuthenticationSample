using AuthenticationSample.Api.Cors;
using AuthenticationSample.Authentication.Grpc.Services;
using AuthenticationSample.Logging;

var builder = WebApplication.CreateBuilder(args);

// Load secrets into configuration

builder.AddSecrets("authentication");

builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true);

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
if (builder.Environment.IsDevelopment())
{
    builder.Services.AddAuthenticationSampleCors(options => builder.Configuration.GetSection("Cors").Bind(options));
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
