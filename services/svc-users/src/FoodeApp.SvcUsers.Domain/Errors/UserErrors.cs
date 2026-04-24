using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Domain.Errors;

public static class UserErrors
{
    public static Error AlreadyExists(string zitadelUserId) =>
        Error.Conflict("User.AlreadyExists", $"Usuário com zitadelUserId '{zitadelUserId}' já existe.");

    public static Error InvalidRole(string value) =>
        Error.Validation("User.InvalidRole", $"Role inválido: '{value}'. Aceitos: comprador, lojista.");

    public static readonly Error InvalidZitadelUserId =
        Error.Validation("User.InvalidZitadelUserId", "zitadelUserId é obrigatório e não pode ser vazio.");

    public static readonly Error InvalidDisplayName =
        Error.Validation("User.InvalidDisplayName", "displayName é obrigatório e não pode ser vazio.");

    public static Error InvalidPhone(string value) =>
        Error.Validation("User.InvalidPhone", $"Telefone '{value}' está em formato inválido.");

    public static Error NotFound(Guid id) =>
        Error.NotFound("User.NotFound", $"Usuário com id '{id}' não encontrado.");
}

