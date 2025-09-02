using AuthSample.Exceptions;
using Grpc.Core;
using Grpc.Core.Interceptors;
using Microsoft.Extensions.Logging;

namespace AuthSample.Api.Exceptions;

public sealed class ExceptionsInterceptor(ILogger<ExceptionsInterceptor> logger) : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        try
        {
            return await continuation(request, context).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IHasGrpcClientError mappedEx)
        {
            logger.LogWarning(ex, "Domain error: {Message}", ex.Message);
            throw mappedEx.ToGrpcError().ToRpcException();
        }
        catch (Exception ex) when (ex is not RpcException)
        {
            logger.LogError(ex, "Unhandled exception");
            // Fallback shape for unexpected errors
            var descriptor = new GrpcErrorDescriptor(
                StatusCode.Internal,
                ErrorCodes.Unexpected,
                Message: "An unexpected error occurred.");
            throw descriptor.ToRpcException();
        }
    }
}
