using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;

namespace FoodeApp.SvcAuth.Application.Queries.GetUserById;

/// <summary>
/// ADR-004: Queries são separadas dos Commands — não passam pelo domínio,
/// podendo ler diretamente de projeções otimizadas (ADR-005).
/// </summary>
public sealed record GetUserByIdQuery(Guid Id) : IRequest<UserProfileDto?>;
