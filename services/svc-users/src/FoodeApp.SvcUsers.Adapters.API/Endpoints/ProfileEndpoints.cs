using MediatR;
using FoodeApp.Svcusers.Adapters.API.Contracts;
using FoodeApp.Svcusers.Adapters.API.Infrastructure;
using FoodeApp.Svcusers.Application.Commands.RegisterUser;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Application.Queries.GetUserById;
using FoodeApp.Svcusers.Application.Queries.GetAllUsers;

namespace FoodeApp.Svcusers.Adapters.API.Endpoints;

internal static class ProfileEndpoints
{
    internal static void MapProfileEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapPost("/profiles", async (RegisterUserRequest request, ISender mediator, CancellationToken ct) =>
        {
            var command = new RegisterUserCommand(
                request.KeycloakId,
                request.DisplayName,
                request.Role,
                request.AvatarUrl,
                request.Phone);

            var result = await mediator.Send(command, ct);

            return result.ToApiResult(profile =>
                Results.Created($"/profiles/{profile.Id}", ApiResponse<UserProfileDto>.Ok(profile)));
        })
        .WithName("RegisterUser")
        .WithTags("Profiles");

        app.MapGet("/profiles/{id:guid}", async (Guid id, ISender mediator, CancellationToken ct) =>
        {
            var result = await mediator.Send(new GetUserByIdQuery(id), ct);

            return result.ToApiResult(profile =>
                profile is null
                    ? Results.NotFound(ApiResponse<UserProfileDto>.Fail("User.NotFound", $"Usuário {id} não encontrado."))
                    : Results.Ok(ApiResponse<UserProfileDto>.Ok(profile)));
        })
        .WithName("GetUserById")
        .WithTags("Profiles");

        app.MapGet("/profiles", async (ISender mediator, CancellationToken ct) =>
        {
            var result = await mediator.Send(new GetAllUsersQuery(), ct);
            return result.ToApiResult();
        })
        .WithName("GetAllUsers")
        .WithTags("Profiles");
    }
}