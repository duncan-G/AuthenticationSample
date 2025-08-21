namespace AuthSample.Auth.Core.Exceptions;

public class DuplicateEmailException : Exception
{
    public DuplicateEmailException(string? message = null) : base(message ?? "A user with this email already exists.")
    {
    }
}
