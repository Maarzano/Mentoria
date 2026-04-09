using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Domain.Primitives;
using MediatR;

namespace FoodeApp.Svcusers.Application.Queries.GetAllUsers;
public sealed record GetAllUsersQuery() : IRequest<Result<IReadOnlyList<UserProfileDto>>>;