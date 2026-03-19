using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;

namespace FoodeApp.SvcAuth.Application.Commands.RegisterUser;

/// <summary>
/// Registra um novo perfil de usuário após a criação da conta no Keycloak (ADR-026).
/// O keycloakId é o claim 'sub' do JWT já validado pelo Kong (ADR-009) e
/// injetado como header X-User-Id pelo gateway.
/// </summary>
public sealed record RegisterUserCommand(
    string KeycloakId,
    string DisplayName,
    string Role,
    string? AvatarUrl,
    string? Phone) : IRequest<UserProfileDto>;
