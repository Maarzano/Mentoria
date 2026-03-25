using FoodeApp.Kernel.Configuration;
using FoodeApp.Kernel.Observability;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Serilog;
using Serilog.Formatting.Json;

namespace FoodeApp.Kernel.Extensions;

public static class SerilogExtensions
{
    /// <summary>
    /// Configura Serilog com console (legível em dev, JSON em prod) + sink OTLP
    /// para o OTel Collector → Loki (ADR-018).
    /// </summary>
    public static IHostBuilder AddFoodeAppSerilog(this IHostBuilder hostBuilder)
    {
        return hostBuilder.UseSerilog((ctx, services, cfg) =>
        {
            var otelSettings = services.GetRequiredService<IOptions<ObservabilitySettings>>().Value;

            if (string.IsNullOrWhiteSpace(otelSettings.ServiceName))
            {
                throw new InvalidOperationException(
                    "Configuracao de observabilidade incompleta. Defina Observability__ServiceName.");
            }

            var otlpEndpoint = otelSettings.OtlpEndpoint?.TrimEnd('/');
            var hasOtlp = !string.IsNullOrWhiteSpace(otlpEndpoint);

            if (!hasOtlp && !ctx.HostingEnvironment.IsDevelopment())
            {
                throw new InvalidOperationException(
                    "Configuracao de observabilidade incompleta. Defina Observability__OtlpEndpoint (ou OTEL_EXPORTER_OTLP_ENDPOINT) em staging/producao.");
            }

            cfg
                .MinimumLevel.Is(ctx.HostingEnvironment.IsDevelopment()
                    ? Serilog.Events.LogEventLevel.Debug
                    : Serilog.Events.LogEventLevel.Information)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("service", otelSettings.ServiceName)
                .Enrich.WithProperty("environment", ctx.HostingEnvironment.EnvironmentName)
                .Enrich.With(new ActivityEnricher());

            if (ctx.HostingEnvironment.IsDevelopment())
                cfg.WriteTo.Console(
                    outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext} [TraceId={TraceId} SpanId={SpanId}]{NewLine}             {Message:lj}{NewLine}{Exception}");
            else
                cfg.WriteTo.Console(new JsonFormatter());

            if (hasOtlp)
            {
                cfg.WriteTo.OpenTelemetry(options =>
                {
                    options.Endpoint = $"{otlpEndpoint}/v1/logs";
                    options.Protocol = Serilog.Sinks.OpenTelemetry.OtlpProtocol.HttpProtobuf;
                    options.ResourceAttributes = new Dictionary<string, object>
                    {
                        ["service.name"] = otelSettings.ServiceName,
                        ["deployment.environment"] = ctx.HostingEnvironment.EnvironmentName
                    };
                });
            }
        });
    }
}
