using System.Diagnostics;
using Serilog.Core;
using Serilog.Events;

namespace FoodeApp.Kernel.Observability;

/// <summary>
/// Enricher Serilog que adiciona TraceId, SpanId e ParentSpanId do Activity.Current
/// em cada log event. Permite correlação log↔trace no Grafana (Loki → Tempo).
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
