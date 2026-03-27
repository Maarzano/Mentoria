using FoodeApp.SvcAuth.Application.Commands.RegisterUser;
using FoodeApp.SvcAuth.Application.Ports;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.Primitives;
using FluentAssertions;
using NSubstitute;

namespace FoodeApp.SvcAuth.Application.Tests.Commands;

public sealed class RegisterUserCommandHandlerTests
{
    private readonly IUserWriteRepository _writeRepository = Substitute.For<IUserWriteRepository>();
    private readonly IUserReadRepository _readRepository = Substitute.For<IUserReadRepository>();
    private readonly IUserEventPublisher _publisher = Substitute.For<IUserEventPublisher>();
    private readonly IUnitOfWork _unitOfWork = Substitute.For<IUnitOfWork>();
    private readonly RegisterUserCommandHandler _handler;

    public RegisterUserCommandHandlerTests()
    {
        _handler = new RegisterUserCommandHandler(_writeRepository, _readRepository, _publisher, _unitOfWork);
    }

    [Fact]
    public async Task Handle_ComDadosValidos_DeveRetornarSucesso()
    {
        _readRepository.ExistsByKeycloakIdAsync(Arg.Any<string>()).Returns(false);

        var command = new RegisterUserCommand("kc-001", "Ana Costa", "comprador", null, null);

        var result = await _handler.Handle(command, CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.KeycloakId.Should().Be("kc-001");
        result.Value.DisplayName.Should().Be("Ana Costa");
        result.Value.Role.Should().Be("comprador");
        await _writeRepository.Received(1).AddAsync(Arg.Any<Domain.Entities.User>());
        await _publisher.Received(1).PublishUserRegisteredAsync(Arg.Any<Domain.Events.UserRegisteredEvent>());
        await _unitOfWork.Received(1).BeginAsync(Arg.Any<CancellationToken>());
        await _unitOfWork.Received(1).CommitAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_QuandoKeycloakIdJaExiste_DeveRetornarConflict()
    {
        _readRepository.ExistsByKeycloakIdAsync("kc-dup").Returns(true);

        var command = new RegisterUserCommand("kc-dup", "Duplicado", "lojista", null, null);

        var result = await _handler.Handle(command, CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.Error.Kind.Should().Be(ErrorKind.Conflict);
        result.Error.Code.Should().Be("User.AlreadyExists");
        await _writeRepository.DidNotReceive().AddAsync(Arg.Any<Domain.Entities.User>());
        await _unitOfWork.DidNotReceive().BeginAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_ComRoleInvalido_DeveRetornarValidationError()
    {
        _readRepository.ExistsByKeycloakIdAsync(Arg.Any<string>()).Returns(false);

        var command = new RegisterUserCommand("kc-002", "João", "admin", null, null);

        var result = await _handler.Handle(command, CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.Error.Kind.Should().Be(ErrorKind.Validation);
        result.Error.Code.Should().Be("User.InvalidRole");
    }

    [Fact]
    public async Task Handle_ComTelefoneValido_DeveRetornarSucessoComPhone()
    {
        _readRepository.ExistsByKeycloakIdAsync(Arg.Any<string>()).Returns(false);

        var command = new RegisterUserCommand("kc-003", "Maria", "lojista", null, "11999887766");

        var result = await _handler.Handle(command, CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Phone.Should().Be("11999887766");
    }
}
