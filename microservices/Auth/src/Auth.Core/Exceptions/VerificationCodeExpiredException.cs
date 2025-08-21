namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeExpiredException : Exception
{
    public VerificationCodeExpiredException(string? message = null) : base(message ?? "The verification code has expired.")
    {
    }
}


