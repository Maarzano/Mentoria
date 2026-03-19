using FoodeApp.SvcAuth.Application.Commands.RegisterUser;
using FoodeApp.SvcAuth.Domain.Exceptions;
using FoodeApp.SvcAuth.Domain.Ports;
using FluentAssertions;
using NSubstitute;

namespace FoodeApp.SvcAuth.Application.Tests.Commands;

public sealed class RegisterUserCommandHandlerTests
{
    private readonly IUserRepository _repository = Substitute.For<IUserRepository>();
    private readonly IUserEventPublisher _publisher = Substitute.For<IUserEventPublisher>();
    private readonly RegisterUserCommandHandler _handler;

    public RegisterUserCommandHandlerTests()
    {
        _handler = new RegisterUserCommandHandler(_repository, _publisher);
    }

    [Fact]
    public async Task Handle_ComDadosValidos_DeveRetornarPerfil()
    {
        _repository.ExistsByKeycloakIdAsync(Arg.Any<string>()).Returns(false);

        var command = new RegisterUserCommand("kc-001", "Ana Costa", "comprador", null, null);

        var result = await _handler.Handle(command, CancellationToken.None);

        result.KeycloakId.Should().Be("kc-001");
        result.DisplayName.Should().Be("Ana Costa");
        result.Role.Should().Be("comprador");
        await _repository.Received(1).AddAsync(Arg.Any<Domain.Entities.User>());
        await _publisher.Received(1).PublishUserRegisteredAsync(Arg.Any<Domain.Events.UserRegisteredEvent>());
    }

    [Fact]
    public async Task Handle_QuandoKeycloakIdJaExiste_DeveLancarUserAlreadyExistsException()
    {
        _repository.ExistsByKeycloakIdAsync("kc-dup").Returns(true);

        var command = new RegisterUserCommand("kc-dup", "Duplicado", "lojista", null, null);

        var act = async () => await _handler.Handle(command, CancellationToken.None);

        await act.Should().ThrowAsync<UserAlreadyExistsException>();
        await _repository.DidNotReceive().AddAsync(Arg.Any<Domain.Entities.User>());
    }
}
