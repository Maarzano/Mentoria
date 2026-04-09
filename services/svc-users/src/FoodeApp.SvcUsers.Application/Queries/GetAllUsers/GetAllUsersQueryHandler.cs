using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Application.Ports;
using FoodeApp.Svcusers.Domain.Primitives;
using MediatR;

namespace FoodeApp.Svcusers.Application.Queries.GetAllUsers;

public sealed class GetAllUsersQueryHandler(IUserReadRepository readRepository)
    : IRequestHandler<GetAllUsersQuery, Result<IReadOnlyList<UserProfileDto>>>
{
    public async Task<Result<IReadOnlyList<UserProfileDto>>> Handle(GetAllUsersQuery query, CancellationToken ct)
    {
        var users = await readRepository.FindAllAsync(ct);
        return Result<IReadOnlyList<UserProfileDto>>.Success(users);
    }
}