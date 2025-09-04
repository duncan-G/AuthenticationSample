using Google.Rpc;
using Grpc.Core;
using StackExchange.Redis;
using Envoy.Service.Auth.V3;
using AuthSample.Authentication;

namespace AuthSample.Auth.Grpc.Services.Internal;

public sealed class AuthorizationService(
    IConnectionMultiplexer cache,
    TokenValidationParametersHelper tokenParameterHelper,
    ILogger<AuthorizationService> logger) : Authorization.AuthorizationBase
{
    public override async Task<CheckResponse> Check(CheckRequest request, ServerCallContext context)
    {
        var cookieHeader = request.Attributes.Request.Http.Headers
            .FirstOrDefault(h => h.Key.Equals("cookie", StringComparison.OrdinalIgnoreCase)).Value;

        var result = await AuthorizationValidationHelper.ValidateFromCookieHeaderAsync(
            cookieHeader,
            cache,
            tokenParameterHelper,
            logger,
            context.CancellationToken).ConfigureAwait(false);

        if (result.IsValid && result.Session is not null)
        {
            return AllowedResponse(result.Session);
        }

        return DeniedResponse(result.FailureCode ?? StatusCode.PermissionDenied, result.FailureMessage ?? "Unauthorized");
    }

    private static CheckResponse AllowedResponse(SessionData data)
    {
        var okResponse = new OkHttpResponse();
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "x-user-sub", Value = data.Sub } });

        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)Code.Ok },
            OkResponse = okResponse
        };
    }

    private static CheckResponse DeniedResponse(StatusCode statusCode, string message)
    {
        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)statusCode, Message = message }
        };
    }
}
