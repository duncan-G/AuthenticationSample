using AuthSample.Auth.Core.Identity;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;


namespace AuthSample.Auth.Grpc.Services;

public sealed class AuthorizationService(
    IIdentityService identityService)
    : Protos.AuthorizationService.AuthorizationServiceBase
{
    public override async Task<Empty> Check(Empty request, ServerCallContext context)
    {
        var cookieHeader = context.GetHttpContext().Request.Headers.Cookie.ToString();

        var session = await identityService.ResolveSessionAsync(
            cookieHeader,
            context.CancellationToken).ConfigureAwait(false);

        if (session is not null)
        {
            return new Empty();
        }

        throw new RpcException(new Status(StatusCode.PermissionDenied, "Unauthorized"));
    }
}
