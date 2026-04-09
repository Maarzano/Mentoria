using FoodeApp.Svcusers.Application.DTOs;

namespace FoodeApp.Svcusers.Application.Ports;

/// <summary>
/// Porta de leitura (read side): retorna DTOs diretamente, sem passar pelo Domain.
/// Usado exclusivamente pelos Query handlers — segue ADR-004 (CQRS) e ADR-005.
/// Implementado por Adapters.Data com SQL explícito mapeando direto para DTO.
/// </summary>
public interface IUserReadRepository
{
    Task<bool> ExistsByKeycloakIdAsync(string keycloakId, CancellationToken ct = default);
    Task<UserProfileDto?> FindByIdAsync(Guid id, CancellationToken ct = default);
    Task<IReadOnlyList<UserProfileDto>> FindAllAsync(CancellationToken ct = default);
}
