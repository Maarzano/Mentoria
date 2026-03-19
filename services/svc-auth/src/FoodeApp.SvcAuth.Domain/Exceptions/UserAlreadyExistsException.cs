namespace FoodeApp.SvcAuth.Domain.Exceptions;

/// <summary>
/// Levantada quando se tenta registrar um keycloakId que já existe no sistema.
/// Mapeada para HTTP 409 Conflict pelo adapter de entrada (Adapters.API).
/// </summary>
public sealed class UserAlreadyExistsException(string keycloakId)
    : Exception($"Usuário com keycloakId '{keycloakId}' já existe.");
