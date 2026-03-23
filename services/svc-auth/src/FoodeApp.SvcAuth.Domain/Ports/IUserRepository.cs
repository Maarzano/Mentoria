using FoodeApp.SvcAuth.Domain.Entities;

namespace FoodeApp.SvcAuth.Domain.Ports;

/// <summary>
/// Porta de saída (outbound port): contrato de persistência do agregado User.
/// Implementado por Adapters.Data (Npgsql/PostgreSQL).
/// O Domain não conhece nada sobre banco de dados.
/// </summary>
public interface IUserRepository
{
    Task<User?> FindByIdAsync(Guid id, CancellationToken ct = default);
    Task<bool> ExistsByKeycloakIdAsync(string keycloakId, CancellationToken ct = default);
    Task AddAsync(User user, CancellationToken ct = default);
    Task<IReadOnlyList<User>> FindAllAsync(CancellationToken ct = default);
}
