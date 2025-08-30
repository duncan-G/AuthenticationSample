using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class VerificationCodeMismatchException(string? message = null)
    : Exception(message ?? "The verification code is incorrect."), IHasGrpcClientError
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.InvalidArgument, ErrorCodes.VerificationCodeMismatch, Message);
}


