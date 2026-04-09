using MediatR;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Application.Mappings;
using FoodeApp.Svcusers.Application.Ports;
using FoodeApp.Svcusers.Domain.Entities;
using FoodeApp.Svcusers.Domain.Errors;
using FoodeApp.Svcusers.Domain.Ports;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Application.Commands.RegisterUser;

public sealed class RegisterUserCommandHandler(
    IUserWriteRepository writeRepository,
    IUserReadRepository readRepository,
    IUserEventPublisher eventPublisher,
    IUnitOfWork unitOfWork)
    : IRequestHandler<RegisterUserCommand, Result<UserProfileDto>>
{
    public async Task<Result<UserProfileDto>> Handle(RegisterUserCommand command, CancellationToken ct)
    {
        if (await readRepository.ExistsByKeycloakIdAsync(command.KeycloakId, ct))
            return UserErrors.AlreadyExists(command.KeycloakId);

        var userResult = User.Register(
            Guid.NewGuid(), command.KeycloakId, command.DisplayName,
            command.Role, command.AvatarUrl, command.Phone);

        if (userResult.IsFailure)
            return userResult.Error;

        var user = userResult.Value;

        await unitOfWork.BeginAsync(ct);
        try
        {
            await writeRepository.AddAsync(user, ct);

            foreach (var @event in user.DomainEvents)
                await eventPublisher.PublishUserRegisteredAsync(@event, ct);

            user.ClearDomainEvents();
            await unitOfWork.CommitAsync(ct);
        }
        catch
        {
            await unitOfWork.RollbackAsync(ct);
            throw;
        }

        return user.ToUserProfileDto();
    }
}
