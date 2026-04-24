using FluentValidation;
using FoodeApp.Svcusers.Domain.ValueObjects;

namespace FoodeApp.Svcusers.Application.Commands.RegisterUser;

public sealed class RegisterUserCommandValidator : AbstractValidator<RegisterUserCommand>
{
    public RegisterUserCommandValidator()
    {
        RuleFor(x => x.ZitadelUserId)
            .NotEmpty().WithMessage("zitadelUserId é obrigatório.");

        RuleFor(x => x.DisplayName)
            .NotEmpty().WithMessage("displayName é obrigatório.")
            .MaximumLength(200).WithMessage("displayName deve ter no máximo 200 caracteres.");

        RuleFor(x => x.Role)
            .NotEmpty().WithMessage("role é obrigatório.")
            .Must(r => UserRoleExtensions.TryParse(r).IsSuccess)
            .WithMessage("role deve ser 'comprador' ou 'lojista'.")
            .When(x => !string.IsNullOrWhiteSpace(x.Role));

        RuleFor(x => x.Phone)
            .MaximumLength(20).WithMessage("phone deve ter no máximo 20 caracteres.")
            .Must(p => PhoneNumber.Create(p!).IsSuccess)
            .WithMessage("phone deve conter entre 10 e 15 dígitos.")
            .When(x => !string.IsNullOrWhiteSpace(x.Phone));

        RuleFor(x => x.AvatarUrl)
            .MaximumLength(500).WithMessage("avatarUrl deve ter no máximo 500 caracteres.")
            .When(x => x.AvatarUrl is not null);
    }
}
