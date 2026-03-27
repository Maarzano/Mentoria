using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Application.Mappings;
using FoodeApp.SvcAuth.Application.Ports;
using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.Errors;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.Primitives;

namespace FoodeApp.SvcAuth.Application.Commands.RegisterUser;

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
