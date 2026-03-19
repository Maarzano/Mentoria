using FoodeApp.SvcAuth.Domain.Events;
using FoodeApp.SvcAuth.Domain.ValueObjects;

namespace FoodeApp.SvcAuth.Domain.Entities;

/// <summary>
/// Aggregate Root do contexto de Auth.
/// Representa o perfil de aplicação do usuário após o cadastro no Keycloak (ADR-026).
/// O Keycloak cuida de autenticação; este agregado cuida dos dados de domínio.
/// </summary>
public sealed class User
{
    private readonly List<UserRegisteredEvent> _domainEvents = [];

    public Guid Id { get; private set; }
    public string KeycloakId { get; private set; } = default!;
    public string DisplayName { get; private set; } = default!;
    public string? AvatarUrl { get; private set; }
    public string? Phone { get; private set; }
    public UserRole Role { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public IReadOnlyList<UserRegisteredEvent> DomainEvents => _domainEvents;

    private User() { }

    /// <summary>
    /// Factory de criação: valida invariantes do domínio e levanta o domain event.
    /// </summary>
    public static User Register(
        Guid id,
        string keycloakId,
        string displayName,
        UserRole role,
        string? avatarUrl = null,
        string? phone = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(keycloakId);
        ArgumentException.ThrowIfNullOrWhiteSpace(displayName);

        var user = new User
        {
            Id = id,
            KeycloakId = keycloakId.Trim(),
            DisplayName = displayName.Trim(),
            AvatarUrl = string.IsNullOrWhiteSpace(avatarUrl) ? null : avatarUrl.Trim(),
            Phone = string.IsNullOrWhiteSpace(phone) ? null : phone.Trim(),
            Role = role,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        user._domainEvents.Add(new UserRegisteredEvent(id, keycloakId, displayName, role));
        return user;
    }

    /// <summary>
    /// Factory de reconstituição: chamada exclusivamente pela camada de persistência
    /// para rehidratar o agregado a partir do banco — não levanta domain events.
    /// </summary>
    public static User Rehydrate(
        Guid id,
        string keycloakId,
        string displayName,
        string? avatarUrl,
        string? phone,
        UserRole role,
        DateTimeOffset createdAt,
        DateTimeOffset updatedAt) => new()
    {
        Id = id,
        KeycloakId = keycloakId,
        DisplayName = displayName,
        AvatarUrl = avatarUrl,
        Phone = phone,
        Role = role,
        CreatedAt = createdAt,
        UpdatedAt = updatedAt,
    };

    public void ClearDomainEvents() => _domainEvents.Clear();
}
