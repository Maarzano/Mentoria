using Npgsql;

namespace FoodeApp.SvcAuth.Adapters.API.Endpoints;

internal static class HealthEndpoints
{
    internal static void MapHealthEndpoints(this IEndpointRouteBuilder app)
    {
        // Liveness: serviço está de pé (ADR-018)
        app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }))
           .ExcludeFromDescription();

        // Readiness: serviço está pronto para receber tráfego — verifica DB
        app.MapGet("/ready", async (NpgsqlDataSource db, CancellationToken ct) =>
        {
            try
            {
                await using var conn = await db.OpenConnectionAsync(ct);
                await using var cmd  = new NpgsqlCommand("SELECT 1", conn);
                var result = await cmd.ExecuteScalarAsync(ct);

                return Convert.ToInt32(result) == 1
                    ? Results.Ok(new { status = "ready" })
                    : Results.StatusCode(StatusCodes.Status503ServiceUnavailable);
            }
            catch
            {
                return Results.StatusCode(StatusCodes.Status503ServiceUnavailable);
            }
        })
        .ExcludeFromDescription();
    }
}
