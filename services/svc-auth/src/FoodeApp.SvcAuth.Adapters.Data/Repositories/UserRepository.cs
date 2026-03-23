using Npgsql;
using FoodeApp.SvcAuth.Domain.Entities;
using FoodeApp.SvcAuth.Domain.Ports;
using FoodeApp.SvcAuth.Domain.ValueObjects;

namespace FoodeApp.SvcAuth.Adapters.Data.Repositories;

/// <summary>
/// Implementação da porta IUserRepository usando Npgsql + PostgreSQL (ADR-003).
/// SQL explícito sem ORM — facilita controle total de queries e performance.
/// </summary>
internal sealed class UserRepository(NpgsqlDataSource dataSource) : IUserRepository
{
    public async Task<User?> FindByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sql = """
            SELECT id, keycloak_id, display_name, avatar_url, phone, role, created_at, updated_at
            FROM auth.users
            WHERE id = @id;
            """;

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var cmd  = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("id", id);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct) ? Hydrate(reader) : null;
    }
    public async Task<IReadOnlyList<User>> FindAllAsync(CancellationToken ct = default)
    {
        const string sql = """
            SELECT id, keycloak_id, display_name, avatar_url, phone, role, created_at, updated_at
            FROM auth.users
            ORDER BY created_at DESC;
            """;
        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var cmd = new NpgsqlCommand(sql, conn);
        await using var reader = await cmd.ExecuteReaderAsync(ct);

        var users = new List<User>();
        while (await reader.ReadAsync(ct))
            users.Add(Hydrate(reader));

        return users;
    }

    public async Task<bool> ExistsByKeycloakIdAsync(string keycloakId, CancellationToken ct = default)
    {
        const string sql = "SELECT 1 FROM auth.users WHERE keycloak_id = @keycloak_id LIMIT 1;";

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var cmd  = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("keycloak_id", keycloakId);

        return await cmd.ExecuteScalarAsync(ct) is not null;
    }

    public async Task AddAsync(User user, CancellationToken ct = default)
    {
        const string sql = """
            INSERT INTO auth.users (id, keycloak_id, display_name, avatar_url, phone, role)
            VALUES (@id, @keycloak_id, @display_name, @avatar_url, @phone, @role);
            """;

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var cmd  = new NpgsqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("id",           user.Id);
        cmd.Parameters.AddWithValue("keycloak_id",  user.KeycloakId);
        cmd.Parameters.AddWithValue("display_name", user.DisplayName);
        cmd.Parameters.AddWithValue("avatar_url",   (object?)user.AvatarUrl ?? DBNull.Value);
        cmd.Parameters.AddWithValue("phone",        (object?)user.Phone     ?? DBNull.Value);
        cmd.Parameters.AddWithValue("role",         user.Role.ToDbValue());

        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static User Hydrate(NpgsqlDataReader r) => User.Rehydrate(
        r.GetGuid(0),
        r.GetString(1),
        r.GetString(2),
        r.IsDBNull(3) ? null : r.GetString(3),
        r.IsDBNull(4) ? null : r.GetString(4),
        UserRoleExtensions.Parse(r.GetString(5)),
        new DateTimeOffset(DateTime.SpecifyKind(r.GetFieldValue<DateTime>(6), DateTimeKind.Utc)),
        new DateTimeOffset(DateTime.SpecifyKind(r.GetFieldValue<DateTime>(7), DateTimeKind.Utc)));
}
