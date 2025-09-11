using System.Linq;
using System.Text.Json;
using Google.Rpc;
using Grpc.Core;
using StackExchange.Redis;
using Envoy.Service.Auth.V3;
using AuthSample.Authentication;
using Microsoft.Extensions.Options;
using AuthSample.Auth.Core.Identity;

namespace AuthSample.Auth.Grpc.Services.Internal;

public sealed class InternalAuthorizationService(
    IIdentityService identityService) : Authorization.AuthorizationBase
{
    public override async Task<CheckResponse> Check(CheckRequest request, ServerCallContext context)
    {
        // Safely read the cookie header from ext_authz request attributes
        string? cookieHeader = null;
        var httpAttributes = request.Attributes?.Request?.Http;
        if (httpAttributes?.Headers != null)
        {
            // Try direct map lookup (case-sensitive)
            if (!httpAttributes.Headers.TryGetValue("cookie", out cookieHeader))
            {
                // Fallback to case-insensitive search
                cookieHeader = httpAttributes.Headers
                    .FirstOrDefault(h => h.Key.Equals("cookie", StringComparison.OrdinalIgnoreCase)).Value;
            }
        }

        var session = await identityService.ResolveSessionAsync(
            cookieHeader,
            context.CancellationToken).ConfigureAwait(false);

        if (session is not null)
        {
            return AllowedResponse(session);
        }

        return DeniedResponse(StatusCode.PermissionDenied, "Unauthorized");
    }

    private static CheckResponse AllowedResponse(SessionData data)
    {
        var okResponse = new OkHttpResponse();
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "x-user-sub", Value = data.Sub } });
        // Instruct Envoy to add the access token as an Authorization header to the upstream request
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "authorization", Value = $"Bearer {data.AccessToken}" } });

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
