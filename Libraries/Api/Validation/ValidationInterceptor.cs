using FluentValidation;
using FluentValidation.Results;
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace AuthenticationSample.Api.Validation;

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
            return await continuation(request, context);
        }

        ValidationResult? result = await validator.ValidateAsync(request);
        if (result.IsValid)
        {
            return await continuation(request, context);
        }

        // Combine error messages
        string errorMessages = string.Join("; ", result.Errors.Select(e => e.ErrorMessage));
        throw new RpcException(new Status(StatusCode.InvalidArgument, errorMessages));
    }
}
