using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.ValueObjects;
using MediatR;

namespace FoodeApp.SvcAuth.Application.Queries.GetAllUsers;
public sealed class GetAllUsersQueryHandler(IUserRepository userRepository)
    : IRequestHandler<GetAllUsersQuery, IReadOnlyList<UserProfileDto>>
{
    public async Task<IReadOnlyList<UserProfileDto>> Handle(GetAllUsersQuery query, CancellationToken ct)
    {
        var users = await userRepository.FindAllAsync(ct);
        return users.Select(ToDto).ToArray();
    }

    private static UserProfileDto ToDto(User user) => new(
        user.Id,
        user.KeycloakId,
        user.DisplayName,
        user.AvatarUrl,
        user.Phone,
        user.Role.ToDbValue(),
        user.CreatedAt,
        user.UpdatedAt);
}