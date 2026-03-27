using FoodeApp.SvcAuth.Adapters.API.Contracts;
using Microsoft.AspNetCore.Diagnostics;

namespace FoodeApp.SvcAuth.Adapters.API.Infrastructure;

/// <summary>
/// Handler global de exceções não tratadas.
/// Transforma qualquer exceção escapada em ApiResponse padronizado com 500.
/// </summary>
public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        logger.LogError(exception, "Exceção não tratada: {Message}", exception.Message);

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        httpContext.Response.ContentType = "application/json";

        var response = ApiResponse<object>.Fail("InternalError", "Erro interno do servidor.");
        await httpContext.Response.WriteAsJsonAsync(response, cancellationToken);

        return true;
    }
}
