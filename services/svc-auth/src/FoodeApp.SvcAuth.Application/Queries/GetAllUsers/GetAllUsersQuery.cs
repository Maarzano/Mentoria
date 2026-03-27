using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Primitives;
using MediatR;

namespace FoodeApp.SvcAuth.Application.Queries.GetAllUsers;
public sealed record GetAllUsersQuery() : IRequest<Result<IReadOnlyList<UserProfileDto>>>;