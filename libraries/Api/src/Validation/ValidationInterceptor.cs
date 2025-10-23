using FluentValidation;
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace AuthSample.Api.Validation;

public sealed class ValidationInterceptor(IServiceProvider serviceProvider) : Interceptor
{
    public override async Task<TResponse> UnaryServerHandler<TRequest, TResponse>(
        TRequest request,
        ServerCallContext context,
        UnaryServerMethod<TRequest, TResponse> continuation)
    {
        // Try to get a validator for the TRequest type
        if (serviceProvider.GetService(typeof(IValidator<TRequest>)) is not IValidator<TRequest> validator)
        {
            return await continuation(request, context).ConfigureAwait(false);
        }

        var result = await validator.ValidateAsync(request).ConfigureAwait(false);
        if (result.IsValid)
        {
            return await continuation(request, context).ConfigureAwait(false);
        }

        var errorCodes = result.Errors.Select(e => e.ErrorCode);
        var errorMessages = result.Errors.Select(e => e.ErrorMessage);
        var metadata = new Metadata {
            { "Error-Codes", string.Join(",", errorCodes) },
            { "Messages", string.Join(",", errorMessages) }
        };
        throw new RpcException(new Status(StatusCode.InvalidArgument, "Bad request"), metadata);
    }
}
