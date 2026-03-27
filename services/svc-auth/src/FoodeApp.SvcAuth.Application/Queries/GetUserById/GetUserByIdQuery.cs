using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Primitives;

namespace FoodeApp.SvcAuth.Application.Queries.GetUserById;
public sealed record GetUserByIdQuery(Guid Id) : IRequest<Result<UserProfileDto?>>;
