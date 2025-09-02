using AuthSample.Auth.Grpc.Protos;
using AuthSample.Exceptions;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class InitiateSignUpRequestValidator : AbstractValidator<InitiateSignUpRequest>
{
	public InitiateSignUpRequestValidator()
	{
		RuleFor(x => x.EmailAddress)
			.NotEmpty().WithErrorCode(ErrorCodes.MissingParameter).WithMessage("Email address is required.")
			.EmailAddress().WithErrorCode(ErrorCodes.InvalidParameter).WithMessage("Email address is not valid.");

		// Password is optional; validate only when provided
		When(x => !string.IsNullOrWhiteSpace(x.Password), () =>
		{
			RuleFor(x => x.Password!)
				.MinimumLength(8).WithErrorCode(ErrorCodes.InvalidLength).WithMessage("Password must be at least 8 characters when provided.")
				.Matches("[A-Za-z]").WithErrorCode(ErrorCodes.InvalidParameter).WithMessage("Password must contain at least one letter when provided.")
				.Matches("\\d").WithErrorCode(ErrorCodes.InvalidParameter).WithMessage("Password must contain at least one number when provided.");

            RuleFor(x => x.RequirePassword)
                .Must(x => x)
                .WithErrorCode(ErrorCodes.InvalidParameter)
                .WithMessage("RequirePassword must be true, when password is provided");
        });
	}
}


