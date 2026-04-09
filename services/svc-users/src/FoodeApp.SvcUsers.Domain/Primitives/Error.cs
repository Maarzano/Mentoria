namespace FoodeApp.Svcusers.Domain.Primitives;

public sealed record Error(string Code, string Message, ErrorKind Kind = ErrorKind.Failure)
{
    public static readonly Error None = new(string.Empty, string.Empty);

    public static Error Conflict(string code, string message) => new(code, message, ErrorKind.Conflict);
    public static Error NotFound(string code, string message) => new(code, message, ErrorKind.NotFound);
    public static Error Validation(string code, string message) => new(code, message, ErrorKind.Validation);
    public static Error Unexpected(string code, string message) => new(code, message, ErrorKind.Unexpected);
}

public enum ErrorKind
{
    Failure,
    Validation,
    NotFound,
    Conflict,
    Unexpected
}
