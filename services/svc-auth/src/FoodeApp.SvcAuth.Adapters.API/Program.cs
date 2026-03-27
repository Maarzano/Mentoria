using FluentMigrator.Runner;
using FluentValidation;
using FoodeApp.Kernel.Configuration;
using FoodeApp.Kernel.Extensions;
using FoodeApp.SvcAuth.Adapters.Data.Extensions;
using FoodeApp.SvcAuth.Adapters.Messaging.Extensions;
using FoodeApp.SvcAuth.Adapters.API.Endpoints;
using FoodeApp.SvcAuth.Adapters.API.Infrastructure;
using FoodeApp.SvcAuth.Adapters.API.Middleware;
using FoodeApp.SvcAuth.Application.Behaviors;
using FoodeApp.SvcAuth.Application.Commands.RegisterUser;
using MediatR;
using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using Prometheus;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// ── .env (dev local sem proj.ps1) ─────────────────────────────────────────────
builder.AddFoodeAppEnv();

// ── Settings (IOptions<T>) ────────────────────────────────────────────────────
builder.Services
    .Configure<DatabaseSettings>(builder.Configuration.GetSection("Database"))
    .Configure<ObservabilitySettings>(builder.Configuration.GetSection("Observability"));

// ── Logging estruturado (ADR-018) ─────────────────────────────────────────────
builder.Host.AddFoodeAppSerilog();

// ── Database ──────────────────────────────────────────────────────────────────
builder.Services.AddFoodeAppDatabase(builder.Configuration);
builder.Services.AddSvcAuthData();

// ── Messaging ─────────────────────────────────────────────────────────────────
builder.Services.AddSvcAuthMessaging();

// ── FluentValidation ──────────────────────────────────────────────────────────
builder.Services.AddValidatorsFromAssemblyContaining<RegisterUserCommandValidator>();

// ── Application (CQRS via MediatR — ADR-004) ─────────────────────────────────
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssemblyContaining<RegisterUserCommandHandler>());

// Pipeline behaviors — ordem: Validation → Logging → Tracing → Handler
builder.Services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationPipelineBehavior<,>));
builder.Services.AddTransient(typeof(IPipelineBehavior<,>), typeof(LoggingPipelineBehavior<,>));
builder.Services.AddTransient(typeof(IPipelineBehavior<,>), typeof(TracingPipelineBehavior<,>));

// ── API ───────────────────────────────────────────────────────────────────────
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
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
builder.Services.AddProblemDetails();

// ── Observabilidade (ADR-018) ─────────────────────────────────────────────────
builder.Services.AddFoodeAppObservability(
    builder.Configuration,
    configureTracing: t => t
        .AddSource("FoodeApp.SvcAuth.Application"),
    configureMetrics: m => m
        .AddMeter("FoodeApp.SvcAuth.Application"));

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
app.UseExceptionHandler();
app.UseMiddleware<KongHeadersMiddleware>();
app.UseHttpMetrics();

// ── Migrações (FluentMigrator) ────────────────────────────────────────────────
using (var scope = app.Services.CreateScope())
{
    var runner = scope.ServiceProvider.GetRequiredService<IMigrationRunner>();
    runner.MigrateUp();
}

// ── Endpoints infra (sem versão — contratos fixos com K8s, ADR-011) ──────────
app.MapHealthEndpoints();
app.MapMetrics("/metrics");

// ── Endpoints de negócio v1 ───────────────────────────────────────────────────
app.MapGroup("/v1")
   .MapProfileEndpoints();

await app.RunAsync();
