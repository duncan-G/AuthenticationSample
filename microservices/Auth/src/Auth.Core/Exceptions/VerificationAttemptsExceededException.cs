namespace AuthSample.Auth.Core.Exceptions;

public class VerificationAttemptsExceededException : Exception
{
    public VerificationAttemptsExceededException(string? message = null) : base(message ?? "Too many verification attempts. Please wait before trying again.")
    {
    }
}


