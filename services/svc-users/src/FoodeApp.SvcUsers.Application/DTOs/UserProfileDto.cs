namespace FoodeApp.Svcusers.Application.DTOs;

/// <summary>
/// DTO de leitura — trafega da Application para o Adapter de entrada (API).
/// Nunca expõe o agregado User diretamente para fora da camada de domínio.
/// </summary>
public sealed record UserProfileDto(
    Guid Id,
    string KeycloakId,
    string DisplayName,
    string? AvatarUrl,
    string? Phone,
    string Role,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);