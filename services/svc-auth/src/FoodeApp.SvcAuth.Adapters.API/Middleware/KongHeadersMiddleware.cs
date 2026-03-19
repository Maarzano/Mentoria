namespace FoodeApp.SvcAuth.Adapters.API.Middleware;

/// <summary>
/// Lê os headers de identidade injetados pelo Kong (ADR-009) após validar o JWT (ADR-026).
/// Os serviços internos confiam nesses headers — nunca revalidam o token JWT diretamente.
///
/// Headers injetados pelo Kong:
///   X-User-Id    → claim 'sub' do JWT (UUID do usuário no Keycloak)
///   X-User-Roles → roles do usuário (ex: "comprador" ou "lojista")
///
/// Os valores ficam disponíveis em HttpContext.Items para uso nos endpoints.
/// </summary>
public sealed class KongHeadersMiddleware(RequestDelegate next)
{
    public const string UserIdKey    = "X-User-Id";
    public const string UserRolesKey = "X-User-Roles";

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.Request.Headers.TryGetValue("X-User-Id", out var userId))
            context.Items[UserIdKey] = userId.ToString();

        if (context.Request.Headers.TryGetValue("X-User-Roles", out var roles))
            context.Items[UserRolesKey] = roles.ToString();

        await next(context);
    }
}
