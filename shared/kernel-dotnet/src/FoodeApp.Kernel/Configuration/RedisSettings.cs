namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações de conexão ao Redis (ADR-012).
/// Seção: "Redis" no appsettings.json.
/// </summary>
public sealed class RedisSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Password { get; set; } = string.Empty;

    public string ConnectionString =>
        string.IsNullOrWhiteSpace(Password)
            ? $"{Host}:{Port}"
            : $"{Host}:{Port},password={Password}";
}
