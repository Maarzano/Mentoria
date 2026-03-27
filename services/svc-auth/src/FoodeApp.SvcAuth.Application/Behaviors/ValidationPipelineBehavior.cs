using FluentValidation;
using FoodeApp.SvcAuth.Domain.Primitives;
using MediatR;

namespace FoodeApp.SvcAuth.Application.Behaviors;

/// <summary>
/// Executa FluentValidation antes do handler.
/// Se houver erros, retorna Result.Failure com ErrorKind.Validation sem chamar o handler.
/// </summary>
public sealed class ValidationPipelineBehavior<TRequest, TResponse>
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    private readonly IEnumerable<IValidator<TRequest>> _validators;

    public ValidationPipelineBehavior(IEnumerable<IValidator<TRequest>> validators)
        => _validators = validators;

    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        if (!_validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);

        var failures = (await Task.WhenAll(
                _validators.Select(v => v.ValidateAsync(context, cancellationToken))))
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count == 0)
            return await next();

        var message = string.Join("; ", failures.Select(f => f.ErrorMessage));
        var error = Error.Validation("Validation", message);

        // TResponse pode ser Result<T> — tenta criar via implicit operator
        if (typeof(TResponse).IsGenericType &&
            typeof(TResponse).GetGenericTypeDefinition() == typeof(Result<>))
        {
            var failureMethod = typeof(TResponse).GetMethod("Failure")!;
            return (TResponse)failureMethod.Invoke(null, [error])!;
        }

        // TResponse é Result (não genérico)
        if (typeof(TResponse) == typeof(Result))
            return (TResponse)(object)Result.Failure(error);

        throw new ValidationException(failures);
    }
}
