using AuthSample.Auth.Grpc.Protos;
using AuthSample.Exceptions;
using FluentValidation;

namespace AuthSample.Auth.Grpc.Validators.SignUp;

public sealed class ResendVerificationCodeRequestValidator : AbstractValidator<ResendVerificationCodeRequest>
{
    public ResendVerificationCodeRequestValidator()
    {
        RuleFor(x => x.EmailAddress)
            .NotEmpty().WithErrorCode(ErrorCodes.MissingParameter).WithMessage("Email address is required.")
            .EmailAddress().WithErrorCode(ErrorCodes.InvalidParameter).WithMessage("Email address is not valid.");
    }
}