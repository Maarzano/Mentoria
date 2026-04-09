using FoodeApp.Svcusers.Domain.ValueObjects;

namespace FoodeApp.Svcusers.Domain.Events;

/// <summary>
/// Domain event emitido quando um novo usuário completa o registro de perfil.
/// Publicado via Outbox (ADR-017) → RabbitMQ (ADR-006) para que o
/// svc-notifications dispare o e-mail/push de boas-vindas.
/// </summary>
public sealed record UserRegisteredEvent(
    Guid UserId,
    string KeycloakId,
    string DisplayName,
    UserRole Role,
    DateTimeOffset OccurredAt)
{
    public UserRegisteredEvent(Guid userId, string keycloakId, string displayName, UserRole role)
        : this(userId, keycloakId, displayName, role, DateTimeOffset.UtcNow) { }
}
