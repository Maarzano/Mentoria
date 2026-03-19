using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.ValueObjects;
using FluentAssertions;

namespace FoodeApp.SvcAuth.Domain.Tests.Entities;

public sealed class UserTests
{
    [Fact]
    public void Register_ComDadosValidos_DeveCriarUsuarioELevantarDomainEvent()
    {
        var id = Guid.NewGuid();

        var user = User.Register(id, "kc-123", "João Silva", UserRole.Comprador);

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
    public void Register_ComKeycloakIdVazio_DeveLancarArgumentException(string keycloakId)
    {
        var act = () => User.Register(Guid.NewGuid(), keycloakId, "Nome", UserRole.Lojista);

        act.Should().Throw<ArgumentException>();
    }

    [Fact]
    public void Register_ComAvatarUrlNula_DeveManterNula()
    {
        var user = User.Register(Guid.NewGuid(), "kc-456", "Maria", UserRole.Comprador);

        user.AvatarUrl.Should().BeNull();
    }

    [Fact]
    public void ClearDomainEvents_DeveEsvaziarALista()
    {
        var user = User.Register(Guid.NewGuid(), "kc-789", "Pedro", UserRole.Lojista);
        user.ClearDomainEvents();

        user.DomainEvents.Should().BeEmpty();
    }
}
