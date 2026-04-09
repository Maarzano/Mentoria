using MediatR;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Application.Commands.RegisterUser;

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
    string? Phone) : IRequest<Result<UserProfileDto>>;
