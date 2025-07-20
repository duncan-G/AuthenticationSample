using OpenTelemetry.Exporter;

namespace AuthenticationSample.Logging;

public class LoggingOptions
{
    public string ServiceName { get; set; } = string.Empty;

    public bool AddSemanticKernelInstrumentation { get; set; }

    public bool EnableSemanticKernelSensitiveDiagnostics { get; set; }

    public bool AddAwsInstrumentation { get; set; }

    public string[] AdditionalTraceSources { get; set; } = [];

    public string[] AdditionalMeters { get; set; } = [];

    public string OtlpEndPoint { get; set; } = string.Empty;

    public OtlpExportProtocol OtlpProtocol { get; set; }
}
