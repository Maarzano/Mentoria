using FoodeApp.SvcAuth.Domain.Entities;

namespace FoodeApp.SvcAuth.Domain.Ports;

/// <summary>
/// Porta de saída (write side): contrato de persistência do agregado User.
/// Usado exclusivamente pelos Command handlers — nunca pelas Queries.
/// Implementado por Adapters.Data dentro de um IUnitOfWork (transação explícita).
/// </summary>
public interface IUserWriteRepository
{
    Task AddAsync(User user, CancellationToken ct = default);
}
