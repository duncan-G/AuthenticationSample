namespace AuthSample.Auth.Core.Exceptions;

public class UserWithEmailNotFoundException : Exception
{
    public UserWithEmailNotFoundException(string? message = null) : base(message ?? "No user with the specified email was found.")
    {
    }
}


