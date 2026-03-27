using FoodeApp.SvcAuth.Domain.Errors;
using FoodeApp.SvcAuth.Domain.Primitives;

namespace FoodeApp.SvcAuth.Domain.ValueObjects;

public enum UserRole
{
    Comprador,
    Lojista
}

public static class UserRoleExtensions
{
    /// <summary>Converte string do request/banco para o enum de domínio.</summary>
    public static UserRole Parse(string value) =>
        value?.Trim().ToLowerInvariant() switch
        {
            "comprador" => UserRole.Comprador,
            "lojista"   => UserRole.Lojista,
            _ => throw new ArgumentException(
                $"Role inválido: '{value}'. Valores aceitos: comprador, lojista.", nameof(value))
        };

    /// <summary>Tenta converter string para UserRole retornando Result.</summary>
    public static Result<UserRole> TryParse(string? value) =>
        value?.Trim().ToLowerInvariant() switch
        {
            "comprador" => Result<UserRole>.Success(UserRole.Comprador),
            "lojista"   => Result<UserRole>.Success(UserRole.Lojista),
            _ => UserErrors.InvalidRole(value ?? "")
        };

    /// <summary>Converte para o valor que é persistido no banco.</summary>
    public static string ToDbValue(this UserRole role) =>
        role switch
        {
            UserRole.Comprador => "comprador",
            UserRole.Lojista   => "lojista",
            _ => throw new ArgumentOutOfRangeException(nameof(role))
        };
}
