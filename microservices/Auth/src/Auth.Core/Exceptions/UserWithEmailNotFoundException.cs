using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class UserWithEmailNotFoundException(string? message = null)
    : Exception(message ?? "No user with the specified email was found."), IHasGrpcClientError
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.NotFound, ErrorCodes.UserNotFound, Message);
}


