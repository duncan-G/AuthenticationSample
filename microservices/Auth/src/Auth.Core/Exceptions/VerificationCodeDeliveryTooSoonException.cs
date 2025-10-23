using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeDeliveryTooSoonException(string? message = null)
    : Exception(message ?? "Verification code was requested too recently. Please wait before trying again.")
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.ResourceExhausted, ErrorCodes.VerificationAttemptsExceeded, Message);
}
