namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeDeliveryTooSoonException : Exception
{
    public VerificationCodeDeliveryTooSoonException(string? message = null) : base(message ??
        "Verification code was requested too recently. Please wait before trying again.")
    {
    }
}
