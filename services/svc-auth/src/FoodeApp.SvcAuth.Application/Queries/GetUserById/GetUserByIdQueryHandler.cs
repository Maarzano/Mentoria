using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.ValueObjects;

namespace FoodeApp.SvcAuth.Application.Queries.GetUserById;

public sealed class GetUserByIdQueryHandler(IUserRepository userRepository)
    : IRequestHandler<GetUserByIdQuery, UserProfileDto?>
{
    public async Task<UserProfileDto?> Handle(GetUserByIdQuery query, CancellationToken ct)
    {
        var user = await userRepository.FindByIdAsync(query.Id, ct);
        if (user is null) return null;

        return new UserProfileDto(
            user.Id,
            user.KeycloakId,
            user.DisplayName,
            user.AvatarUrl,
            user.Phone,
            user.Role.ToDbValue(),
            user.CreatedAt,
            user.UpdatedAt);
    }
}
