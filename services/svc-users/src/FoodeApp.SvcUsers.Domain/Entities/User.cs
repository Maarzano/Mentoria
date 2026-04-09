using FoodeApp.Svcusers.Domain.Errors;
using FoodeApp.Svcusers.Domain.Events;
using FoodeApp.Svcusers.Domain.Primitives;
using FoodeApp.Svcusers.Domain.ValueObjects;

namespace FoodeApp.Svcusers.Domain.Entities;

/// <summary>
/// Aggregate Root do contexto de users.
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
    public PhoneNumber? Phone { get; private set; }
    public UserRole Role { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }
    public DateTimeOffset UpdatedAt { get; private set; }

    public IReadOnlyList<UserRegisteredEvent> DomainEvents => _domainEvents;

    private User() { }

    /// <summary>
    /// Factory de criação: valida invariantes do domínio, cria value objects
    /// a partir dos inputs brutos e levanta o domain event.
    /// </summary>
    public static Result<User> Register(
        Guid id,
        string keycloakId,
        string displayName,
        string role,
        string? avatarUrl = null,
        string? phone = null)
    {
        if (string.IsNullOrWhiteSpace(keycloakId))
            return UserErrors.InvalidKeycloakId;

        if (string.IsNullOrWhiteSpace(displayName))
            return UserErrors.InvalidDisplayName;

        var roleResult = UserRoleExtensions.TryParse(role);
        if (roleResult.IsFailure)
            return roleResult.Error;

        PhoneNumber? phoneObj = null;
        if (!string.IsNullOrWhiteSpace(phone))
        {
            var phoneResult = PhoneNumber.Create(phone);
            if (phoneResult.IsFailure)
                return phoneResult.Error;
            phoneObj = phoneResult.Value;
        }

        var user = new User
        {
            Id = id,
            KeycloakId = keycloakId.Trim(),
            DisplayName = displayName.Trim(),
            AvatarUrl = string.IsNullOrWhiteSpace(avatarUrl) ? null : avatarUrl.Trim(),
            Phone = phoneObj,
            Role = roleResult.Value,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        user._domainEvents.Add(new UserRegisteredEvent(id, keycloakId, displayName, roleResult.Value));
        return user;
    }

    public void ClearDomainEvents() => _domainEvents.Clear();
}
