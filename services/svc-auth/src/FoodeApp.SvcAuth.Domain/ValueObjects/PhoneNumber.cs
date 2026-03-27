using System.Text.RegularExpressions;
using FoodeApp.SvcAuth.Domain.Errors;
using FoodeApp.SvcAuth.Domain.Primitives;

namespace FoodeApp.SvcAuth.Domain.ValueObjects;

public sealed partial record PhoneNumber
{
    public string Value { get; }

    private PhoneNumber(string value) => Value = value;

    public static Result<PhoneNumber> Create(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return UserErrors.InvalidPhone(input ?? "");

        var digits = DigitsOnly().Replace(input, "");

        if (digits.Length < 10 || digits.Length > 15)
            return UserErrors.InvalidPhone(input);

        return new PhoneNumber(digits);
    }

    [GeneratedRegex(@"[^\d]")]
    private static partial Regex DigitsOnly();
}
