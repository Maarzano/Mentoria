using Dapper;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Application.Ports;
using Npgsql;

namespace FoodeApp.Svcusers.Adapters.Data.Repositories;

/// <summary>
/// Read side do CQRS: mapeia direto do banco para DTO via Dapper, sem passar pelo Domain.
/// Abre sua própria conexão — não precisa de transação (SELECT puro, ADR-005).
/// </summary>
internal sealed class UserReadRepository(NpgsqlDataSource dataSource) : IUserReadRepository
{
    private sealed record UserProfileReadModel(
        Guid Id,
        string KeycloakId,
        string DisplayName,
        string? AvatarUrl,
        string? Phone,
        string Role,
        DateTime CreatedAt,
        DateTime UpdatedAt);

    public async Task<bool> ExistsByKeycloakIdAsync(string keycloakId, CancellationToken ct = default)
    {
        const string sql = "SELECT 1 FROM users.users WHERE keycloak_id = @KeycloakId LIMIT 1;";

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        var result = await conn.ExecuteScalarAsync<int?>(new CommandDefinition(sql, new { KeycloakId = keycloakId }, cancellationToken: ct));
        return result is not null;
    }

    public async Task<UserProfileDto?> FindByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sql = """
            SELECT id           AS "Id",
                   keycloak_id  AS "KeycloakId",
                   display_name AS "DisplayName",
                   avatar_url   AS "AvatarUrl",
                   phone        AS "Phone",
                   role         AS "Role",
                   created_at   AS "CreatedAt",
                   updated_at   AS "UpdatedAt"
              FROM users.users
             WHERE id = @Id;
            """;

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        var row = await conn.QuerySingleOrDefaultAsync<UserProfileReadModel>(
            new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));

        return row is null ? null : ToDto(row);
    }

    public async Task<IReadOnlyList<UserProfileDto>> FindAllAsync(CancellationToken ct = default)
    {
        const string sql = """
            SELECT id           AS "Id",
                   keycloak_id  AS "KeycloakId",
                   display_name AS "DisplayName",
                   avatar_url   AS "AvatarUrl",
                   phone        AS "Phone",
                   role         AS "Role",
                   created_at   AS "CreatedAt",
                   updated_at   AS "UpdatedAt"
              FROM users.users
             ORDER BY created_at DESC;
            """;

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        var rows = await conn.QueryAsync<UserProfileReadModel>(new CommandDefinition(sql, cancellationToken: ct));
        return rows.Select(ToDto).ToList();
    }

    private static UserProfileDto ToDto(UserProfileReadModel row) => new(
        row.Id,
        row.KeycloakId,
        row.DisplayName,
        row.AvatarUrl,
        row.Phone,
        row.Role,
        new DateTimeOffset(DateTime.SpecifyKind(row.CreatedAt, DateTimeKind.Utc)),
        new DateTimeOffset(DateTime.SpecifyKind(row.UpdatedAt, DateTimeKind.Utc)));
}
