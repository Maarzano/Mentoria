using MediatR;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Application.Queries.GetUserById;
public sealed record GetUserByIdQuery(Guid Id) : IRequest<Result<UserProfileDto?>>;
