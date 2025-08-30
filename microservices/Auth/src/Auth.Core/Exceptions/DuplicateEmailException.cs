using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class DuplicateEmailException(string? message = null)
    : Exception(message ?? "A user with this email already exists."), IHasGrpcClientError
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.AlreadyExists, ErrorCodes.DuplicateEmail, Message);
}
