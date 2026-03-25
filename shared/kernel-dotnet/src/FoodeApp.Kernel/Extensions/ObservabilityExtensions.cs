using FoodeApp.Kernel.Configuration;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

namespace FoodeApp.Kernel.Extensions;

public static class ObservabilityExtensions
{
    /// <summary>
    /// Registra OpenTelemetry (tracing + metrics) com exportadores OTLP (ADR-018).
    /// Cada serviço passa suas ActivitySources adicionais para o tracing.
    /// </summary>
    public static IServiceCollection AddFoodeAppObservability(
        this IServiceCollection services,
        IConfiguration configuration,
        Action<TracerProviderBuilder>? configureTracing = null,
        Action<MeterProviderBuilder>? configureMetrics = null)
    {
        services.Configure<ObservabilitySettings>(configuration.GetSection("Observability"));

        services
            .AddOpenTelemetry()
            .ConfigureResource(r =>
            {
                var otel = configuration.GetSection("Observability").Get<ObservabilitySettings>()
                           ?? new ObservabilitySettings();

                r.AddService(otel.ServiceName)
                 .AddAttributes([
                     new("deployment.environment", otel.Environment),
                     new("service.version",
                         typeof(ObservabilityExtensions).Assembly.GetName().Version?.ToString() ?? "0.0.0")
                 ]);
            })
            .WithTracing(t =>
            {
                t.AddAspNetCoreInstrumentation(o =>
                {
                    o.RecordException = true;
                    o.EnrichWithHttpRequest = (activity, request) =>
                    {
                        activity.SetTag("http.request.header.user_agent",
                            request.Headers.UserAgent.ToString());
                        if (request.Headers.TryGetValue("X-User-Id", out var userId))
                            activity.SetTag("enduser.id", userId.ToString());
                    };
                    o.EnrichWithHttpResponse = (activity, response) =>
                    {
                        activity.SetTag("http.response.body.size", response.ContentLength);
                    };
                })
                .AddSource("Npgsql")
                .AddOtlpExporter();

                configureTracing?.Invoke(t);
            })
            .WithMetrics(m =>
            {
                m.AddAspNetCoreInstrumentation()
                 .AddRuntimeInstrumentation()
                 .AddMeter("Npgsql")
                 .AddOtlpExporter();

                configureMetrics?.Invoke(m);
            });

        return services;
    }
}
