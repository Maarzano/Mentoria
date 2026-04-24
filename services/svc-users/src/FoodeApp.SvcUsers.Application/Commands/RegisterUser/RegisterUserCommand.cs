using MediatR;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Application.Commands.RegisterUser;

/// <summary>
/// Registra um novo Application Profile vinculado a uma identidade do ZITADEL (ADR-026).
/// O <c>ZitadelUserId</c> é o claim 'sub' do JWT já validado pelo Kong (ADR-009)
/// e injetado como header <c>X-User-Id</c> pelo gateway.
/// </summary>
public sealed record RegisterUserCommand(
    string ZitadelUserId,
    string DisplayName,
    string Role,
    string? AvatarUrl,
    string? Phone) : IRequest<Result<UserProfileDto>>;

