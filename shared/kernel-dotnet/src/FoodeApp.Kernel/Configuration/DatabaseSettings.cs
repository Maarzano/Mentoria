namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações de conexão ao PostgreSQL.
/// Seção: "Database" no appsettings.json.
/// Segredos (Password) injetados via env var: Database__Password.
/// </summary>
public sealed class DatabaseSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Database { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;

    public string ConnectionString =>
        $"Host={Host};Port={Port};Database={Database};Username={Username};Password={Password};Pooling=true";
}
