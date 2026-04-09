using FoodeApp.Svcusers.Domain.Entities;
using FoodeApp.Svcusers.Domain.ValueObjects;
using FluentAssertions;

namespace FoodeApp.Svcusers.Domain.Tests.Entities;

public sealed class UserTests
{
    [Fact]
    public void Register_ComDadosValidos_DeveCriarUsuarioELevantarDomainEvent()
    {
        var id = Guid.NewGuid();

        var result = User.Register(id, "kc-123", "João Silva", "comprador");

        result.IsSuccess.Should().BeTrue();
        var user = result.Value;
        user.Id.Should().Be(id);
        user.KeycloakId.Should().Be("kc-123");
        user.DisplayName.Should().Be("João Silva");
        user.Role.Should().Be(UserRole.Comprador);
        user.DomainEvents.Should().HaveCount(1);
        user.DomainEvents[0].UserId.Should().Be(id);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Register_ComKeycloakIdVazio_DeveRetornarFalha(string keycloakId)
    {
        var result = User.Register(Guid.NewGuid(), keycloakId, "Nome", "lojista");

        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("User.InvalidKeycloakId");
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Register_ComDisplayNameVazio_DeveRetornarFalha(string displayName)
    {
        var result = User.Register(Guid.NewGuid(), "kc-456", displayName, "comprador");

        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("User.InvalidDisplayName");
    }

    [Fact]
    public void Register_ComRoleInvalido_DeveRetornarFalha()
    {
        var result = User.Register(Guid.NewGuid(), "kc-456", "Maria", "admin");

        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("User.InvalidRole");
    }

    [Fact]
    public void Register_ComPhoneInvalido_DeveRetornarFalha()
    {
        var result = User.Register(Guid.NewGuid(), "kc-456", "Maria", "comprador", phone: "123");

        result.IsFailure.Should().BeTrue();
        result.Error.Code.Should().Be("User.InvalidPhone");
    }

    [Fact]
    public void Register_ComAvatarUrlNula_DeveManterNula()
    {
        var result = User.Register(Guid.NewGuid(), "kc-456", "Maria", "comprador");

        result.IsSuccess.Should().BeTrue();
        result.Value.AvatarUrl.Should().BeNull();
    }

    [Fact]
    public void Register_ComPhoneNumber_DeveArmazenarValor()
    {
        var result = User.Register(Guid.NewGuid(), "kc-456", "Maria", "comprador", phone: "11999887766");

        result.IsSuccess.Should().BeTrue();
        result.Value.Phone.Should().NotBeNull();
        result.Value.Phone!.Value.Should().Be("11999887766");
    }

    [Fact]
    public void ClearDomainEvents_DeveEsvaziarALista()
    {
        var result = User.Register(Guid.NewGuid(), "kc-789", "Pedro", "lojista");
        result.IsSuccess.Should().BeTrue();

        var user = result.Value;
        user.ClearDomainEvents();

        user.DomainEvents.Should().BeEmpty();
    }
}
