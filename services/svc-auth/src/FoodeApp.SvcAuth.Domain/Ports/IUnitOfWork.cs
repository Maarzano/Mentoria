namespace FoodeApp.SvcAuth.Domain.Ports;

/// <summary>
/// Unidade de trabalho: controla a transação que envolve escrita no banco.
/// Garante atomicidade entre AddAsync (User) e PublishAsync (Outbox) — ADR-017.
/// Implementado por Adapters.Data via NpgsqlTransaction.
/// </summary>
public interface IUnitOfWork
{
    Task BeginAsync(CancellationToken ct = default);
    Task CommitAsync(CancellationToken ct = default);
    Task RollbackAsync(CancellationToken ct = default);
}
