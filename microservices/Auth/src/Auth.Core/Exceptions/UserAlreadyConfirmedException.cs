namespace AuthSample.Auth.Core.Exceptions;

public class UserAlreadyConfirmedException(string? message = null)
    : Exception(message ?? "The user has already been confirmed.");

