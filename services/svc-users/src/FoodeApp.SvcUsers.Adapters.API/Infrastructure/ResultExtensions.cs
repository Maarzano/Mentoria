using FoodeApp.Svcusers.Adapters.API.Contracts;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Adapters.API.Infrastructure;

/// <summary>
/// Mapeia Result&lt;T&gt; do domínio para IResult da Minimal API com ApiResponse envelope.
/// </summary>
internal static class ResultExtensions
{
    internal static IResult ToApiResult<T>(this Result<T> result, Func<T, IResult>? onSuccess = null)
    {
        if (result.IsSuccess)
        {
            if (onSuccess is not null)
                return onSuccess(result.Value);

            return Results.Ok(ApiResponse<T>.Ok(result.Value));
        }

        return result.Error.Kind switch
        {
            ErrorKind.Validation => Results.UnprocessableEntity(
                ApiResponse<T>.Fail(result.Error.Code, result.Error.Message)),
            ErrorKind.NotFound => Results.NotFound(
                ApiResponse<T>.Fail(result.Error.Code, result.Error.Message)),
            ErrorKind.Conflict => Results.Conflict(
                ApiResponse<T>.Fail(result.Error.Code, result.Error.Message)),
            _ => Results.Json(
                ApiResponse<T>.Fail(result.Error.Code, result.Error.Message),
                statusCode: StatusCodes.Status500InternalServerError)
        };
    }
}
