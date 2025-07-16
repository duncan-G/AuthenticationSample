using OpenTelemetry.Exporter;

namespace AuthenticationSample.Logging;

public class LoggingOptions
{
    public required string ServiceName { get; set; }

    public bool AddSemanticKernelInstrumentation { get; set; }

    public bool EnableSemanticKernelSensitiveDiagnostics { get; set; }

    public bool AddAwsInstrumentation { get; set; }

    public string[] AdditionalTraceSources { get; set; } = [];

    public string[] AdditionalMeters { get; set; } = [];

    public required string OtlpEndPoint { get; set; }

    public required OtlpExportProtocol OtlpProtocol { get; set; }
}
