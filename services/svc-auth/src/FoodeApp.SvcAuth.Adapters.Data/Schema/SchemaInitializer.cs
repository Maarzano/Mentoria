using Npgsql;

namespace FoodeApp.SvcAuth.Adapters.Data.Schema;

/// <summary>
/// Inicializa o schema auth no PostgreSQL de forma idempotente na subida do serviço.
/// Em produção, isso seria substituído por migrações versionadas (ex: Flyway ou EF Migrations).
/// </summary>
public sealed class SchemaInitializer(NpgsqlDataSource dataSource)
{
    public async Task InitializeAsync(CancellationToken ct = default)
    {
        const string sql = """
            CREATE SCHEMA IF NOT EXISTS auth;

            CREATE TABLE IF NOT EXISTS auth.users
            (
                id           UUID        PRIMARY KEY,
                keycloak_id  TEXT        NOT NULL UNIQUE,
                display_name TEXT        NOT NULL,
                avatar_url   TEXT        NULL,
                phone        TEXT        NULL,
                role         TEXT        NOT NULL CHECK (role IN ('comprador', 'lojista')),
                created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            -- Tabela Outbox para eventos de domínio (ADR-017)
            -- Publicada pelo OutboxWorker → RabbitMQ (ADR-006). Ainda não ativo.
            CREATE TABLE IF NOT EXISTS auth.outbox_messages
            (
                id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
                type         TEXT        NOT NULL,
                payload      JSONB       NOT NULL,
                created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                published_at TIMESTAMPTZ NULL,
                retry_count  INT         NOT NULL DEFAULT 0
            );
            """;

        await using var conn = await dataSource.OpenConnectionAsync(ct);
        await using var cmd  = new NpgsqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}
