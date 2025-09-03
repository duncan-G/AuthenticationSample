using AuthSample.Auth.Grpc.Protos;
using AuthSample.Exceptions;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class VerifyAndSignInRequestValidator : AbstractValidator<VerifyAndSignInRequest>
{
	public VerifyAndSignInRequestValidator()
	{
		RuleFor(x => x.EmailAddress)
			.NotEmpty().WithErrorCode(ErrorCodes.MissingParameter).WithMessage("Email address is required.")
			.EmailAddress().WithMessage("Email address is not valid.");

		RuleFor(x => x.VerificationCode)
			.NotEmpty().WithErrorCode(ErrorCodes.MissingParameter).WithMessage("Verification code is required.")
			.Length(6).WithErrorCode(ErrorCodes.InvalidParameter).WithMessage("Verification code must be 6 characters.");

		RuleFor(x => x.Name)
			.MaximumLength(100).WithErrorCode(ErrorCodes.InvalidLength).WithMessage("Name must be at most 100 characters.");
	}
}


