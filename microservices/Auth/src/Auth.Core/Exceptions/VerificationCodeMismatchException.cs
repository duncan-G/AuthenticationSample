namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeMismatchException : Exception
{
    public VerificationCodeMismatchException(string? message = null) : base(message ?? "The verification code is incorrect.")
    {
    }
}


