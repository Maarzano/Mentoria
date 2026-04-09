using FoodeApp.Svcusers.Domain.Entities;
using FoodeApp.Svcusers.Domain.Ports;
using Microsoft.EntityFrameworkCore;

namespace FoodeApp.Svcusers.Adapters.Data.Repositories;

/// <summary>
/// Write side do CQRS: usa EF Core para persistir o agregado User.
/// Não chama SaveChangesAsync diretamente — o IUnitOfWork é responsável por
/// commitar a transação e persistir todas as mudanças rastreadas de uma vez.
/// </summary>
internal sealed class UserWriteRepository(usersDbContext dbContext) : IUserWriteRepository
{
    public Task AddAsync(User user, CancellationToken ct = default)
    {
        dbContext.Users.Add(user);
        return Task.CompletedTask;
    }
}
