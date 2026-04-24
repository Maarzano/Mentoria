using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Domain.Entities;
using FoodeApp.Svcusers.Domain.ValueObjects;

namespace FoodeApp.Svcusers.Application.Mappings;

internal static class UserProfileDtoMappings
{
    internal static UserProfileDto ToUserProfileDto(this User user) => new(
        user.Id,
        user.ZitadelUserId,
        user.DisplayName,
        user.AvatarUrl,
        user.Phone?.Value,
        user.Role.ToDbValue(),
        user.CreatedAt,
        user.UpdatedAt);
}
