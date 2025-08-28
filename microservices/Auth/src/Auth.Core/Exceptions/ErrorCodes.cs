namespace AuthSample.Auth.Core.Exceptions;

public static class ErrorCodes
{
    public const string DuplicateEmail = "1001";
    public const string UserNotFound = "1002";

    public const string VerificationCodeMismatch = "2001";
    public const string VerificationCodeExpired = "2002";
    public const string VerificationAttemptsExceeded = "2003";
    public const string VerificationCodeDeliveryFailed = "2004";

    public const string Unexpected = "9999";
}


