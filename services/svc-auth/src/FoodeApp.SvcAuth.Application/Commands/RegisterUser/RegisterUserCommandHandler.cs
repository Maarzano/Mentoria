using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.Exceptions;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.ValueObjects;

namespace FoodeApp.SvcAuth.Application.Commands.RegisterUser;

public sealed class RegisterUserCommandHandler(
    IUserRepository userRepository,
    IUserEventPublisher eventPublisher)
    : IRequestHandler<RegisterUserCommand, UserProfileDto>
{
    public async Task<UserProfileDto> Handle(RegisterUserCommand command, CancellationToken ct)
    {
        if (await userRepository.ExistsByKeycloakIdAsync(command.KeycloakId, ct))
            throw new UserAlreadyExistsException(command.KeycloakId);

        var role = UserRoleExtensions.Parse(command.Role);
        var user = User.Register(Guid.NewGuid(), command.KeycloakId, command.DisplayName, role, command.AvatarUrl, command.Phone);

        await userRepository.AddAsync(user, ct);

        foreach (var @event in user.DomainEvents)
            await eventPublisher.PublishUserRegisteredAsync(@event, ct);

        user.ClearDomainEvents();

        return ToDto(user);
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
