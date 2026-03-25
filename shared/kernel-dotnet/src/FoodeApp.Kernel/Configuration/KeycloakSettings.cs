namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações do Keycloak como Identity Provider (ADR-026).
/// Seção: "Keycloak" no appsettings.json.
/// </summary>
public sealed class KeycloakSettings
{
    public string RealmUrl { get; set; } = string.Empty;
    public string ClientId { get; set; } = string.Empty;
}
