using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeExpiredException(string? message = null)
    : Exception(message ?? "The verification code has expired.")
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.ResourceExhausted, ErrorCodes.VerificationCodeExpired, Message);
}


