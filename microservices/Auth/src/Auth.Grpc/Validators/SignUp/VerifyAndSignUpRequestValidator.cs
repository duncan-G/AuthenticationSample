using AuthSample.Auth.Grpc.Protos;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class VerifyAndSignUpRequestValidator : AbstractValidator<VerifyAndSignUpRequest>
{
	public VerifyAndSignUpRequestValidator()
	{
		RuleFor(x => x.EmailAddress)
			.NotEmpty().WithMessage("Email address is required.")
			.EmailAddress().WithMessage("Email address is not valid.");

		RuleFor(x => x.VerificationCode)
			.NotEmpty().WithMessage("Verification code is required.")
			.Length(6).WithMessage("Verification code must be 6 characters.");

		RuleFor(x => x.Name)
			.NotEmpty().WithMessage("Name is required.")
			.MaximumLength(100).WithMessage("Name must be at most 100 characters.");
	}
}


