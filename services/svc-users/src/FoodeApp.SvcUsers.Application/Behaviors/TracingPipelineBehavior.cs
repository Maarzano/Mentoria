using System.Diagnostics;
using MediatR;

namespace FoodeApp.Svcusers.Application.Behaviors;

/// <summary>
/// MediatR Pipeline Behavior que envolve cada Command/Query handler em um
/// Activity span do OpenTelemetry (ADR-018).
///
/// Gera spans filhos como:
///   "RegisterUserCommand" (kind=Internal, dentro do span HTTP pai)
///   "GetAllUsersQuery"    (kind=Internal, dentro do span HTTP pai)
///
/// Tags adicionais:
///   mediatr.request.type  → nome completo do tipo do request
///   mediatr.request.kind  → "command" ou "query"
///   mediatr.status        → "success" ou "error"
///
/// Em caso de exceção, grava o status Error + evento de exceção no span.
/// </summary>
public sealed class TracingPipelineBehavior<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    internal static readonly ActivitySource ActivitySource = new("FoodeApp.Svcusers.Application");

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        var requestName = typeof(TRequest).Name;
        using var activity = ActivitySource.StartActivity(requestName, ActivityKind.Internal);

        if (activity is not null)
        {
            activity.SetTag("mediatr.request.type", typeof(TRequest).FullName);
            activity.SetTag("mediatr.response.type", typeof(TResponse).FullName);

            var isCommand = requestName.Contains("Command", StringComparison.OrdinalIgnoreCase);
            activity.SetTag("mediatr.request.kind", isCommand ? "command" : "query");
        }

        try
        {
            var response = await next();
            activity?.SetTag("mediatr.status", "success");
            return response;
        }
        catch (Exception ex)
        {
            if (activity is not null)
            {
                activity.SetStatus(ActivityStatusCode.Error, ex.Message);
                activity.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
                {
                    { "exception.type", ex.GetType().FullName },
                    { "exception.message", ex.Message },
                    { "exception.stacktrace", ex.StackTrace }
                }));
            }

            throw;
        }
    }
}
