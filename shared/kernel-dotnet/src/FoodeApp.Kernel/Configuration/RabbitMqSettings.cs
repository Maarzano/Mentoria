namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações de conexão ao RabbitMQ (ADR-006).
/// Seção: "RabbitMq" no appsettings.json.
/// </summary>
public sealed class RabbitMqSettings
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}
