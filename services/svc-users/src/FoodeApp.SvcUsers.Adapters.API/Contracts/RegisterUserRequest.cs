namespace FoodeApp.Svcusers.Adapters.API.Contracts;

/// <summary>
/// DTO de entrada da API — desacoplado do Command para permitir
/// transformações/versionamento de contrato sem afetar a Application layer.
/// </summary>
public sealed record RegisterUserRequest(
    string ZitadelUserId,
    string DisplayName,
    string Role,
    string? AvatarUrl,
    string? Phone);
