using AuthSample.Auth.Grpc.Protos;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class IsEmailTakenRequestValidator : AbstractValidator<IsEmailTakenRequest>
{
	public IsEmailTakenRequestValidator()
	{
		RuleFor(x => x.EmailAddress)
			.NotEmpty().WithMessage("Email address is required.")
			.EmailAddress().WithMessage("Email address is not valid.");
	}
}


