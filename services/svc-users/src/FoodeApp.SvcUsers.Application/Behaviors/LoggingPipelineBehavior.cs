using System.Diagnostics;
using FoodeApp.Svcusers.Domain.Primitives;
using MediatR;
using Microsoft.Extensions.Logging;

namespace FoodeApp.Svcusers.Application.Behaviors;

/// <summary>
/// Centraliza logging estruturado para todos os handlers.
/// Registra início, sucesso/falha e duração de cada request.
/// </summary>
public sealed class LoggingPipelineBehavior<TRequest, TResponse>(
    ILogger<LoggingPipelineBehavior<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        var requestName = typeof(TRequest).Name;
        logger.LogDebug("Handling {RequestName} {@Request}", requestName, request);

        var sw = Stopwatch.StartNew();

        try
        {
            var response = await next();
            sw.Stop();

            if (IsResultFailure(response))
            {
                var error = ExtractError(response);
                logger.LogWarning(
                    "Handled {RequestName} with failure [{ErrorCode}] {ErrorMessage} in {ElapsedMs}ms",
                    requestName, error.Code, error.Message, sw.ElapsedMilliseconds);
            }
            else
            {
                logger.LogInformation(
                    "Handled {RequestName} successfully in {ElapsedMs}ms",
                    requestName, sw.ElapsedMilliseconds);
            }

            return response;
        }
        catch (Exception ex)
        {
            sw.Stop();
            logger.LogError(ex,
                "Handled {RequestName} with exception in {ElapsedMs}ms",
                requestName, sw.ElapsedMilliseconds);
            throw;
        }
    }

    private static bool IsResultFailure(TResponse response)
    {
        if (response is Result r)
            return r.IsFailure;

        var type = typeof(TResponse);
        if (type.IsGenericType && type.GetGenericTypeDefinition() == typeof(Result<>))
        {
            var prop = type.GetProperty("IsFailure")!;
            return (bool)prop.GetValue(response)!;
        }

        return false;
    }

    private static Error ExtractError(TResponse response)
    {
        if (response is Result r)
            return r.Error;

        var prop = typeof(TResponse).GetProperty("Error")!;
        return (Error)prop.GetValue(response)!;
    }
}
