using MediatR;
using FoodeApp.Svcusers.Application.DTOs;
using FoodeApp.Svcusers.Application.Ports;
using FoodeApp.Svcusers.Domain.Primitives;

namespace FoodeApp.Svcusers.Application.Queries.GetUserById;

public sealed class GetUserByIdQueryHandler(IUserReadRepository readRepository)
    : IRequestHandler<GetUserByIdQuery, Result<UserProfileDto?>>
{
    public async Task<Result<UserProfileDto?>> Handle(GetUserByIdQuery query, CancellationToken ct)
    {
        var dto = await readRepository.FindByIdAsync(query.Id, ct);
        return Result<UserProfileDto?>.Success(dto);
    }
}
