using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.ValueObjects;

namespace FoodeApp.SvcAuth.Application.Mappings;

internal static class UserProfileDtoMappings
{
    internal static UserProfileDto ToUserProfileDto(this User user) => new(
        user.Id,
        user.KeycloakId,
        user.DisplayName,
        user.AvatarUrl,
        user.Phone?.Value,
        user.Role.ToDbValue(),
        user.CreatedAt,
        user.UpdatedAt);
}
