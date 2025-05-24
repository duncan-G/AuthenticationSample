using AuthenticationSample.Authentication.Grpc.Services;
using AuthenticationSample.Logging;
using dotenv.net;

var builder = WebApplication.CreateBuilder(args);

// Load secrets into configuration
DotEnv.Load();
builder.Configuration
    .AddJsonFile("appsettings.json", false, true)
    .AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", true)
    .AddEnvironmentVariables("Authentication:");

// Configure logging
builder.AddLogging(options =>
{
    options.ServiceName = "Authentication";
    options.AddAWSInstrumentation = true;
});

// Add mapping
builder.Services.AddAutoMapper(typeof(Program));

// Add health checks
builder.Services.AddHealthChecks();

// Add services to the container.
builder.Services.AddGrpc();

var app = builder.Build();

app.UseGrpcWeb();

// Configure the HTTP request pipeline.
app.MapGrpcService<GreeterService>().EnableGrpcWeb();
app.MapGet("/",
    () =>
        "Communication with gRPC endpoints must be made through a gRPC client. To learn how to create a client, visit: https://go.microsoft.com/fwlink/?linkid=2086909");

app.MapHealthChecks("/health");

app.Run();