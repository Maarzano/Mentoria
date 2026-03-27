using MediatR;
using FoodeApp.SvcAuth.Application.DTOs;
using FoodeApp.SvcAuth.Application.Ports;
using FoodeApp.SvcAuth.Domain.Primitives;

namespace FoodeApp.SvcAuth.Application.Queries.GetUserById;

public sealed class GetUserByIdQueryHandler(IUserReadRepository readRepository)
    : IRequestHandler<GetUserByIdQuery, Result<UserProfileDto?>>
{
    public async Task<Result<UserProfileDto?>> Handle(GetUserByIdQuery query, CancellationToken ct)
    {
        var dto = await readRepository.FindByIdAsync(query.Id, ct);
        return Result<UserProfileDto?>.Success(dto);
    }
}
