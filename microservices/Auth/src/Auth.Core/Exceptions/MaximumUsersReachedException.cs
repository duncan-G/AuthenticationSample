using AuthSample.Exceptions;
using Grpc.Core;

namespace AuthSample.Auth.Core.Exceptions;

public class MaximumUsersReachedException(string? message = null)
    : Exception(message ?? "Maximum users reached."), IHasGrpcClientError
{
    public GrpcErrorDescriptor ToGrpcError() =>
        new (StatusCode.ResourceExhausted, ErrorCodes.MaximumUsersReached, Message);
}
