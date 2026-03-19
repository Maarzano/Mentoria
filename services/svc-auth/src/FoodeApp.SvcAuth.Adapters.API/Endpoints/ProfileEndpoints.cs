using MediatR;
using FoodeApp.SvcAuth.Application.Commands.RegisterUser;
using FoodeApp.SvcAuth.Application.Queries.GetUserById;
using FoodeApp.SvcAuth.Domain.Exceptions;

namespace FoodeApp.SvcAuth.Adapters.API.Endpoints;

internal static class ProfileEndpoints
{
    internal static void MapProfileEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/profiles", async (RegisterUserRequest request, ISender mediator, CancellationToken ct) =>
        {
            var errors = ValidateRequest(request);
            if (errors.Count > 0)
                return Results.ValidationProblem(errors);

            var command = new RegisterUserCommand(
                request.KeycloakId,
                request.DisplayName,
                request.Role,
                request.AvatarUrl,
                request.Phone);

            try
            {
                var profile = await mediator.Send(command, ct);
                return Results.Created($"/profiles/{profile.Id}", profile);
            }
            catch (UserAlreadyExistsException)
            {
                return Results.Conflict(new { error = "keycloakId já existe." });
            }
        })
        .WithName("RegisterUser")
        .WithTags("Profiles");

        app.MapGet("/profiles/{id:guid}", async (Guid id, ISender mediator, CancellationToken ct) =>
        {
            var profile = await mediator.Send(new GetUserByIdQuery(id), ct);
            return profile is null ? Results.NotFound() : Results.Ok(profile);
        })
        .WithName("GetUserById")
        .WithTags("Profiles");
    }

    private static Dictionary<string, string[]> ValidateRequest(RegisterUserRequest req)
    {
        var errors = new Dictionary<string, string[]>();

        if (string.IsNullOrWhiteSpace(req.KeycloakId))
            errors["keycloakId"] = ["keycloakId é obrigatório."];

        if (string.IsNullOrWhiteSpace(req.DisplayName))
            errors["displayName"] = ["displayName é obrigatório."];

        var role = req.Role?.Trim().ToLowerInvariant() ?? string.Empty;
        if (role != "comprador" && role != "lojista")
            errors["role"] = ["role deve ser: comprador ou lojista."];

        if (!string.IsNullOrWhiteSpace(req.AvatarUrl) &&
            !Uri.TryCreate(req.AvatarUrl, UriKind.Absolute, out _))
            errors["avatarUrl"] = ["avatarUrl deve ser uma URL absoluta válida."];

        return errors;
    }
}

/// <summary>
/// DTO de entrada da API — desacoplado do Command para permitir
/// transformações/versionamento de contrato sem afetar a Application layer.
/// </summary>
internal sealed record RegisterUserRequest(
    string KeycloakId,
    string DisplayName,
    string Role,
    string? AvatarUrl,
    string? Phone);
