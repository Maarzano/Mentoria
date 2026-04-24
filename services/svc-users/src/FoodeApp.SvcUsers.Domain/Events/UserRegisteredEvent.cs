using FoodeApp.Svcusers.Domain.ValueObjects;

namespace FoodeApp.Svcusers.Domain.Events;

/// <summary>
/// Domain event emitido quando um novo usuário completa o registro de perfil.
/// Publicado via Outbox (ADR-017) → RabbitMQ (ADR-006) para que o
/// svc-notifications dispare e-mail/push de boas-vindas.
/// <c>ZitadelUserId</c> é o identificador no IAM (ADR-026).
/// </summary>
public sealed record UserRegisteredEvent(
    Guid UserId,
    string ZitadelUserId,
    string DisplayName,
    UserRole Role,
    DateTimeOffset OccurredAt)
{
    public UserRegisteredEvent(Guid userId, string zitadelUserId, string displayName, UserRole role)
        : this(userId, zitadelUserId, displayName, role, DateTimeOffset.UtcNow) { }
}

