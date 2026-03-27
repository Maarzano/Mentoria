using FoodeApp.SvcAuth.Domain.Ports;
using Microsoft.EntityFrameworkCore.Storage;

namespace FoodeApp.SvcAuth.Adapters.Data;

/// <summary>
/// Implementação do IUnitOfWork usando EF Core + NpgsqlTransaction.
/// CommitAsync chama SaveChangesAsync (persiste o change tracker) e depois
/// commita a transação do banco — garante atomicidade com o Outbox (ADR-017).
/// </summary>
internal sealed class UnitOfWork(AuthDbContext dbContext) : IUnitOfWork
{
    private IDbContextTransaction? _transaction;

    public async Task BeginAsync(CancellationToken ct = default)
    {
        _transaction = await dbContext.Database.BeginTransactionAsync(ct);
    }

    public async Task CommitAsync(CancellationToken ct = default)
    {
        await dbContext.SaveChangesAsync(ct);

        if (_transaction is not null)
            await _transaction.CommitAsync(ct);
    }

    public async Task RollbackAsync(CancellationToken ct = default)
    {
        if (_transaction is not null)
            await _transaction.RollbackAsync(ct);
    }
}
