using System.Diagnostics;
using Serilog.Core;
using Serilog.Events;

namespace FoodeApp.SvcAuth.Adapters.API.Observability;

/// <summary>
/// Enricher Serilog que adiciona TraceId, SpanId e ParentSpanId do Activity.Current
/// em cada log event. Permite correlação log↔trace no Grafana (Loki → Tempo).
///
/// Compatível com Serilog 4.x (substituindo Serilog.Enrichers.Span que é 2.x/3.x only).
/// </summary>
public sealed class ActivityEnricher : ILogEventEnricher
{
    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        var activity = Activity.Current;
        if (activity is null) return;

        logEvent.AddPropertyIfAbsent(propertyFactory.CreateProperty("TraceId", activity.TraceId.ToString()));
        logEvent.AddPropertyIfAbsent(propertyFactory.CreateProperty("SpanId", activity.SpanId.ToString()));

        if (activity.ParentSpanId != default)
            logEvent.AddPropertyIfAbsent(propertyFactory.CreateProperty("ParentSpanId", activity.ParentSpanId.ToString()));
    }
}
