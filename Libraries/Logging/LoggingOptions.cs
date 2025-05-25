namespace AuthenticationSample.Logging;

public class LoggingOptions
{
    public string ServiceName { get; set; } = null!;

    public bool AddSemanticKernelInstrumentation { get; set; }

    public bool EnableSemanticKernelSensitiveDiagnostics { get; set; }

    public bool AddAWSInstrumentation { get; set; }

    public string[] AdditionalTraceSources { get; set; } = [];

    public string[] AdditionalMeters { get; set; } = [];
}