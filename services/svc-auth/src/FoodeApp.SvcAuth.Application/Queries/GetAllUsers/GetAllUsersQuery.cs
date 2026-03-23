using FoodeApp.SvcAuth.Application.DTOs;
using MediatR;

namespace FoodeApp.SvcAuth.Application.Queries.GetAllUsers;
public sealed record GetAllUsersQuery() : IRequest<IReadOnlyList<UserProfileDto>>;