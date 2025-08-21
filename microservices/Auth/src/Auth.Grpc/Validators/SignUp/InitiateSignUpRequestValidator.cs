using AuthSample.Auth.Grpc.Protos;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class InitiateSignUpRequestValidator : AbstractValidator<InitiateSignUpRequest>
{
	public InitiateSignUpRequestValidator()
	{
		RuleFor(x => x.EmailAddress)
			.NotEmpty().WithMessage("Email address is required.")
			.EmailAddress().WithMessage("Email address is not valid.");

		// Password is optional; validate only when provided
		When(x => !string.IsNullOrWhiteSpace(x.Password), () =>
		{
			RuleFor(x => x.Password!)
				.MinimumLength(8).WithMessage("Password must be at least 8 characters when provided.")
				.Matches("[A-Za-z]").WithMessage("Password must contain at least one letter when provided.")
				.Matches("\\d").WithMessage("Password must contain at least one number when provided.");
		});
	}
}


