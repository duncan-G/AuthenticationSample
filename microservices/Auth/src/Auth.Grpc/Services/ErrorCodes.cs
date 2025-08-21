namespace AuthSample.Auth.Grpc.Services;

public static class ErrorCodes
{
    public const string DuplicateEmail = "1001";

    public const string CodeDeliveryFailed = "2001";

    public const string VerificationCodeMismatch = "3001";
    public const string VerificationCodeExpired = "3002";
    public const string VerificationAttemptsExceeded = "3003";
    public const string UserNotFound = "3004";

    public const string CognitoOperationFailed = "9001";
    public const string Unexpected = "9999";
}


