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

    /// <summary>Converte para o valor que é persistido no banco.</summary>
    public static string ToDbValue(this UserRole role) =>
        role switch
        {
            UserRole.Comprador => "comprador",
            UserRole.Lojista   => "lojista",
            _ => throw new ArgumentOutOfRangeException(nameof(role))
        };
}
