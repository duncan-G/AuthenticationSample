using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeDeliveryFailedException(string? message = null)
    : Exception(message ?? "Failed to deliver verification code.")
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.Internal, ErrorCodes.VerificationCodeDeliveryFailed, Message);
}
