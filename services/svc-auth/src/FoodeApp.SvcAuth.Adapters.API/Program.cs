using FoodeApp.SvcAuth.Adapters.Data.Extensions;
using FoodeApp.SvcAuth.Adapters.Data.Schema;
using FoodeApp.SvcAuth.Adapters.Messaging.Extensions;
using FoodeApp.SvcAuth.Adapters.API.Endpoints;
using FoodeApp.SvcAuth.Adapters.API.Middleware;
using FoodeApp.SvcAuth.Application.Commands.RegisterUser;
using Npgsql;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using Prometheus;
using Microsoft.OpenApi.Models;
using Serilog;
using Serilog.Formatting.Json;

var builder = WebApplication.CreateBuilder(args);

// ── Logging estruturado (ADR-018) ─────────────────────────────────────────────
// Dev  → console legível (HH:mm:ss LEVEL SourceContext: mensagem)
// Prod → JSON para Promtail/Loki coletar do stdout
builder.Host.UseSerilog((ctx, cfg) =>
{
    cfg
        .MinimumLevel.Is(ctx.HostingEnvironment.IsDevelopment()
            ? Serilog.Events.LogEventLevel.Debug
            : Serilog.Events.LogEventLevel.Information)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("service", "svc-auth")
        .Enrich.WithProperty("environment", ctx.HostingEnvironment.EnvironmentName);

    if (ctx.HostingEnvironment.IsDevelopment())
        cfg.WriteTo.Console(
            outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}{NewLine}             {Message:lj}{NewLine}{Exception}");
    else
        cfg.WriteTo.Console(new JsonFormatter());
});

// ── Database ──────────────────────────────────────────────────────────────────
var connectionString = ResolveConnectionString(builder.Configuration);
var dataSource = new NpgsqlDataSourceBuilder(connectionString).Build();

// ── Infra Adapters (Ports → Implementations) ──────────────────────────────────
builder.Services.AddSvcAuthData(dataSource);    // IUserRepository → UserRepository
builder.Services.AddSvcAuthMessaging();          // IUserEventPublisher → UserEventPublisher

// ── Application (CQRS via MediatR — ADR-004) ─────────────────────────────────
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssemblyContaining<RegisterUserCommandHandler>());

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "FoodeApp SvcAuth API",
        Version = "v1",
        Description = "API de autenticacao/perfil do FoodeApp"
    });
});

// ── RFC 7807 ProblemDetails — respostas de erro padronizadas em toda a API ───
builder.Services.AddProblemDetails();

// ── Observabilidade (ADR-018) ─────────────────────────────────────────────────
// O SDK do OTel lê OTEL_EXPORTER_OTLP_ENDPOINT do ambiente automaticamente.
// Em local dev sem collector o OTLP falha silenciosamente (sem crash).
// Em staging/produção, a variável é injetada pelo ConfigMap do K8s.
builder.Services
    .AddOpenTelemetry()
    .ConfigureResource(r => r
        .AddService("svc-auth")
        .AddAttributes([new("deployment.environment", builder.Environment.EnvironmentName)]))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation(o => o.RecordException = true)
        .AddSource("Npgsql")          // Instrumentação nativa do driver — queries SQL em traces
        .AddOtlpExporter())           // endpoint via OTEL_EXPORTER_OTLP_ENDPOINT
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddRuntimeInstrumentation()  // GC, thread pool, alocações
        .AddOtlpExporter());

// ── Build ─────────────────────────────────────────────────────────────────────
var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/swagger/v1/swagger.json", "FoodeApp SvcAuth API v1");
        options.RoutePrefix = "swagger";
    });
}

// ── Middlewares ───────────────────────────────────────────────────────────────
// Trata exceções não capturadas como ProblemDetails RFC 7807 (sem stacktrace em produção)
app.UseExceptionHandler();
// Lê headers X-User-Id / X-User-Roles injetados pelo Kong (ADR-009, ADR-026)
app.UseMiddleware<KongHeadersMiddleware>();
// Coleta métricas HTTP para o endpoint /metrics (prometheus-net — ADR-018)
app.UseHttpMetrics();

// ── Schema (idempotente na subida) ────────────────────────────────────────────
await app.Services.GetRequiredService<SchemaInitializer>().InitializeAsync();

// ── Endpoints infra (sem versão — contratos fixos com K8s, ADR-011) ──────────
app.MapHealthEndpoints();
app.MapMetrics("/metrics");

// ── Endpoints de negócio v1 ───────────────────────────────────────────────────
app.MapGroup("/v1")
   .MapProfileEndpoints();

await app.RunAsync();

// ── Helpers ───────────────────────────────────────────────────────────────────
static string ResolveConnectionString(IConfiguration configuration)
{
    var configured = configuration["ConnectionStrings__Default"]
                     ?? configuration.GetConnectionString("Default");
    if (!string.IsNullOrWhiteSpace(configured))
        return configured;

    var host     = configuration["Postgres__Host"]     ?? "postgres";
    var port     = configuration["Postgres__Port"]     ?? "5432";
    var database = configuration["Postgres__Database"] ?? "foodeapp_auth";
    var user     = configuration["Postgres__User"]     ?? "pgadmin";
    var password = configuration["Postgres__Password"]
                   ?? Environment.GetEnvironmentVariable("POSTGRES_PASSWORD");

    if (string.IsNullOrWhiteSpace(password))
        throw new InvalidOperationException(
            "Senha nao configurada. Defina ConnectionStrings__Default ou Postgres__Password.");

    return $"Host={host};Port={port};Database={database};Username={user};Password={password};Pooling=true";
}
