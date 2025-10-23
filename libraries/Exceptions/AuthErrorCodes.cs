namespace AuthSample.Exceptions;

public sealed partial class ErrorCodes
{
    public const string DuplicateEmail = "2000";
    public const string UserNotFound = "2001";

    public const string VerificationCodeMismatch = "2002";
    public const string VerificationCodeExpired = "2003";
    public const string VerificationAttemptsExceeded = "2004";
    public const string VerificationCodeDeliveryFailed = "2005";

    public const string MaximumUsersReached = "2006";

}
