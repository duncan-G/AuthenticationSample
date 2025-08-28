namespace AuthSample.Exceptions;

public interface IHasGrpcClientError
{
    GrpcErrorDescriptor ToGrpcError();
}
