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

var builder = WebApplication.CreateBuilder(args);

// ── Database ──────────────────────────────────────────────────────────────────
var connectionString = ResolveConnectionString(builder.Configuration);
var dataSource = new NpgsqlDataSourceBuilder(connectionString).Build();

// ── Infra Adapters (Ports → Implementations) ──────────────────────────────────
builder.Services.AddSvcAuthData(dataSource);    // IUserRepository → UserRepository
builder.Services.AddSvcAuthMessaging();          // IUserEventPublisher → UserEventPublisher

// ── Application (CQRS via MediatR — ADR-004) ─────────────────────────────────
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssemblyContaining<RegisterUserCommandHandler>());

// ── Observabilidade (ADR-018) ─────────────────────────────────────────────────
builder.Services
    .AddOpenTelemetry()
    .ConfigureResource(r => r.AddService("svc-auth"))
    .WithTracing(t => t
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter())
    .WithMetrics(m => m
        .AddAspNetCoreInstrumentation()
        .AddOtlpExporter());

// ── Build ─────────────────────────────────────────────────────────────────────
var app = builder.Build();

// ── Middlewares ───────────────────────────────────────────────────────────────
// Lê headers X-User-Id / X-User-Roles injetados pelo Kong (ADR-009, ADR-026)
app.UseMiddleware<KongHeadersMiddleware>();
// Coleta métricas HTTP para o endpoint /metrics (prometheus-net — ADR-018)
app.UseHttpMetrics();

// ── Schema (idempotente na subida) ────────────────────────────────────────────
await app.Services.GetRequiredService<SchemaInitializer>().InitializeAsync();

// ── Endpoints ─────────────────────────────────────────────────────────────────
app.MapHealthEndpoints();
app.MapProfileEndpoints();
app.MapMetrics("/metrics");

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
