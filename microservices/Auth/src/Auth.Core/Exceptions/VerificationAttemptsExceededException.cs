using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class VerificationAttemptsExceededException(string? message = null)
    : Exception(message ?? "Too many verification attempts. Please wait before trying again."), IHasGrpcClientError
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.ResourceExhausted, ErrorCodes.VerificationAttemptsExceeded, Message);
}
