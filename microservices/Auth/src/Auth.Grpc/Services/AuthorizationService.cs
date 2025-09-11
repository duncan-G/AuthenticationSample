using AuthSample.Auth.Core.Identity;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;


namespace AuthSample.Auth.Grpc.Services;

public sealed class AuthorizationService(
    IIdentityService identityService)
    : Protos.AuthorizationService.AuthorizationServiceBase
{
    private const string ExpiredRtCookie = "RT_SID=; Path=/; HttpOnly; Secure; SameSite=Strict; Expires=Thu, 01 Jan 1970 00:00:00 GMT";

    public override async Task<Empty> Check(Empty request, ServerCallContext context)
    {
        var cookieHeader = context.GetHttpContext().Request.Headers.Cookie.ToString();

        var resolved = await identityService.ResolveSessionAsync(
            cookieHeader,
            context.CancellationToken).ConfigureAwait(false);

        if (resolved?.Session is null)
        {
            if (resolved is not null && resolved.ShouldClearRefreshCookie)
            {
                await context.WriteResponseHeadersAsync(new Metadata { { "Set-Cookie", ExpiredRtCookie } }).ConfigureAwait(false);
            }
            throw new RpcException(new Status(StatusCode.PermissionDenied, "Unauthorized"));
        }

        if (string.IsNullOrEmpty(resolved.NewAccessTokenId) && resolved.AccessTokenExpiry is null)
        {
            return new Empty();
        }

        var accessTokenCookie = $"AT_SID={resolved.NewAccessTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={resolved.AccessTokenExpiry!.Value.ToUniversalTime():R}";
        await context.WriteResponseHeadersAsync(new Metadata { { "Set-Cookie", accessTokenCookie } }).ConfigureAwait(false);
        return new Empty();

    }
}
