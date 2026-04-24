namespace FoodeApp.Kernel.Configuration;

/// <summary>
/// Configurações do ZITADEL como Identity Provider (ADR-026).
/// Seção: "Zitadel" no appsettings.json.
/// <list type="bullet">
///   <item><c>IssuerUrl</c>: URL do ZITADEL (ex: https://id.foodeapp.com.br). Usado para OIDC discovery/JWKS.</item>
///   <item><c>ProjectId</c>: ID do projeto no ZITADEL (um projeto por tenant FoodeApp).</item>
///   <item><c>WebClientId</c> / <c>MobileClientId</c>: client IDs OIDC (PKCE public clients).</item>
/// </list>
/// </summary>
public sealed class ZitadelSettings
{
    public string IssuerUrl { get; set; } = string.Empty;
    public string ProjectId { get; set; } = string.Empty;
    public string WebClientId { get; set; } = string.Empty;
    public string MobileClientId { get; set; } = string.Empty;
}
