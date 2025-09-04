using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using StackExchange.Redis;

namespace AuthSample.Auth.Grpc.Services;

public sealed class AuthorizationService(
    IConnectionMultiplexer cache,
    TokenValidationParametersHelper tokenParametersHelper,
    ILogger<AuthorizationService> logger)
    : Protos.AuthorizationService.AuthorizationServiceBase
{
    public override async Task<Empty> Check(Empty request, ServerCallContext context)
    {
        var httpContext = context.GetHttpContext();
        var cookieHeader = httpContext.Request.Headers.Cookie.ToString();

        var result = await AuthorizationValidationHelper.ValidateFromCookieHeaderAsync(
            cookieHeader,
            cache,
            tokenParametersHelper,
            logger,
            context.CancellationToken).ConfigureAwait(false);

        if (result.IsValid)
        {
            return new Empty();
        }

        throw new RpcException(new Status(result.FailureCode ?? StatusCode.PermissionDenied, result.FailureMessage ?? "Unauthorized"));
    }
}
