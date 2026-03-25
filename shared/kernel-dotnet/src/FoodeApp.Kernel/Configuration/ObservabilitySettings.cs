namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações de observabilidade (OpenTelemetry + Serilog).
/// Seção: "Observability" no appsettings.json.
/// </summary>
public sealed class ObservabilitySettings
{
    public string OtlpEndpoint { get; set; } = string.Empty;
    public string OtlpProtocol { get; set; } = string.Empty;
    public string ServiceName { get; set; } = string.Empty;
    public string Environment { get; set; } = string.Empty;
}
