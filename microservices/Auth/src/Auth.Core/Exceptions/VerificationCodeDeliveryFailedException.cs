namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeDeliveryFailedException : Exception
{
    public VerificationCodeDeliveryFailedException(string? message = null) : base(message ??
        "Failed to deliver verification code.")
    {
    }
}
