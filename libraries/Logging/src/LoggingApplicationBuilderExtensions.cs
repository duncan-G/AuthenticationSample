using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace AuthSample.Logging;

public static class LoggingApplicationBuilderExtensions
{
    public static IHostApplicationBuilder AddLogging(
        this IHostApplicationBuilder builder,
        Action<LoggingOptions> configureOptions)
    {
        var options = new LoggingOptions();
        configureOptions(options);

        if (options == null)
        {
            throw new InvalidOperationException("Missing required configuration section 'ApplicationOptions'");
        }

        if (string.IsNullOrEmpty(options.ServiceName))
        {
            throw new InvalidOperationException("ServiceName cannot be null or empty.");
        }

        if (string.IsNullOrEmpty(options.OtlpEndPoint))
        {
            throw new InvalidOperationException("OtlpEndPoint cannot be null or empty.");
        }

        var loggingBuilder = builder.Logging
            .AddOpenTelemetry(otlOptions =>
            {
                otlOptions.IncludeFormattedMessage = true;
                otlOptions.IncludeScopes = true;
            });

        if (options is { AddSemanticKernelInstrumentation: true, EnableSemanticKernelSensitiveDiagnostics: true })
        {
            AppContext.SetSwitch("Microsoft.SemanticKernel.Experimental.GenAI.EnableOTelDiagnosticsSensitive", true);
        }

        var otelBuilder = loggingBuilder.Services.AddOpenTelemetry();

        otelBuilder.ConfigureResource(r => r
            .AddAttributes([
                new KeyValuePair<string, object>("service.name", options.ServiceName),
                new KeyValuePair<string, object>("service.instance_id", Environment.MachineName)
            ]));

        otelBuilder
            .WithTracing(traceBuilder =>
            {
                traceBuilder
                    .AddAspNetCoreInstrumentation(aciOptions =>
                    {
                        aciOptions.EnableAspNetCoreSignalRSupport = true;
                        aciOptions.Filter = context =>
                        {
                            var path = context.Request.Path.Value;
                            var isHealthCheck = path?.StartsWith("/healthz", StringComparison.OrdinalIgnoreCase) ?? true;
                            var isOptions = HttpMethods.IsOptions(context.Request.Method);
                            return !isHealthCheck && !isOptions;
                        };
                    })
                    .AddGrpcCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddEntityFrameworkCoreInstrumentation(efiOption => { efiOption.SetDbStatementForText = true; })
                    .AddSource("Npgsql")
                    .AddRedisInstrumentation();
                if (options.AddSemanticKernelInstrumentation)
                {
                    traceBuilder.AddSource("Microsoft.SemanticKernel*");
                }

                if (options.AddAwsInstrumentation)
                {
                    traceBuilder.AddAWSInstrumentation();
                }

                traceBuilder.AddSource("AuthSample.*");
                traceBuilder.AddSource(options.AdditionalTraceSources);
            })
            .WithMetrics(metricsBuilder =>
            {
                metricsBuilder
                    .AddAspNetCoreInstrumentation()
                    .AddHttpClientInstrumentation()
                    .AddRuntimeInstrumentation()
                    .AddProcessInstrumentation()
                    .AddMeter("Npgsql");

                if (options.AddSemanticKernelInstrumentation)
                {
                    metricsBuilder.AddMeter("Microsoft.SemanticKernel*");
                }

                if (options.AddAwsInstrumentation)
                {
                    metricsBuilder.AddAWSInstrumentation();
                }

                metricsBuilder.AddMeter("AuthSample.*");
                metricsBuilder.AddMeter(options.AdditionalMeters);
            })
            .WithLogging();

        builder.Services.AddOpenTelemetry().UseOtlpExporter(
            options.OtlpProtocol,
            new Uri(options.OtlpEndPoint));

        return builder;
    }
}
