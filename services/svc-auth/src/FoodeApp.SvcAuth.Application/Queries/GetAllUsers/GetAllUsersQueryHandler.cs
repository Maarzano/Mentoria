using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Application.Ports;
using FoodeApp.SvcAuth.Domain.Primitives;
using MediatR;

namespace FoodeApp.SvcAuth.Application.Queries.GetAllUsers;

public sealed class GetAllUsersQueryHandler(IUserReadRepository readRepository)
    : IRequestHandler<GetAllUsersQuery, Result<IReadOnlyList<UserProfileDto>>>
{
    public async Task<Result<IReadOnlyList<UserProfileDto>>> Handle(GetAllUsersQuery query, CancellationToken ct)
    {
        var users = await readRepository.FindAllAsync(ct);
        return Result<IReadOnlyList<UserProfileDto>>.Success(users);
    }
}