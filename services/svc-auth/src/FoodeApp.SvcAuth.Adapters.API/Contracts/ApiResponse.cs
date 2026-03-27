namespace FoodeApp.SvcAuth.Adapters.API.Contracts;

/// <summary>
/// Envelope padronizado para todas as respostas da API.
/// </summary>
public sealed record ApiResponse<T>(bool Success, T? Data, ApiErrorDetail? Error)
{
    public static ApiResponse<T> Ok(T data) => new(true, data, null);
    public static ApiResponse<T> Fail(string code, string message) => new(false, default, new(code, message));
}

public sealed record ApiErrorDetail(string Code, string Message);
