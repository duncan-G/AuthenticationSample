using Google.Rpc;
using Grpc.Core;
using Envoy.Service.Auth.V3;
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

        var resolved = await identityService.ResolveSessionAsync(
            cookieHeader,
            context.CancellationToken).ConfigureAwait(false);

        if (resolved?.Session is not null)
        {
            return AllowedResponse(resolved);
        }

        return DeniedResponse(StatusCode.PermissionDenied, "Unauthorized", resolved);
    }

    private static CheckResponse AllowedResponse(ResolvedSession resolved)
    {
        var data = resolved.Session!;
        var okResponse = new OkHttpResponse();

        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "x-user-sub", Value = data.Sub } });
        okResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue { Key = "authorization", Value = $"Bearer {data.AccessToken}" } });

        if (!string.IsNullOrEmpty(resolved.NewAccessTokenId) && resolved.AccessTokenExpiry.HasValue)
        {
            okResponse.ResponseHeadersToAdd.Add(new HeaderValueOption { Header = new HeaderValue {
                Key = "Set-Cookie",
                Value = $"AT_SID={resolved.NewAccessTokenId!}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={resolved.AccessTokenExpiry.Value.ToUniversalTime().ToString("R")}"
            }});
        }

        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)Code.Ok },
            OkResponse = okResponse
        };
    }

    private static CheckResponse DeniedResponse(StatusCode statusCode, string message, ResolvedSession? resolved)
    {
        var deniedResponse = new DeniedHttpResponse();
        if (resolved is not null && resolved.ShouldClearRefreshCookie)
        {
            deniedResponse.Headers.Add(new HeaderValueOption { Header = new HeaderValue {
                Key = "Set-Cookie",
                Value = "RT_SID=; Path=/; HttpOnly; Secure; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT"
            }});
        }

        return new CheckResponse
        {
            Status = new Google.Rpc.Status { Code = (int)statusCode, Message = message },
            DeniedResponse = deniedResponse
        };
    }
}
