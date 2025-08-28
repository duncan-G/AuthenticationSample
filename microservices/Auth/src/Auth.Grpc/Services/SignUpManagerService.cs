using AuthSample.Auth.Core;
using AuthSample.Auth.Grpc.Protos;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using InitiateSignUpRequest = AuthSample.Auth.Grpc.Protos.InitiateSignUpRequest;

namespace AuthSample.Auth.Grpc.Services;

public class SignUpManagerService(
    IIdentityService identityService,
    ILogger<SignUpManagerService> logger) : SignUpManager.SignUpManagerBase
{
    public override async Task<Empty> InitiateSignUpAsync(InitiateSignUpRequest request, ServerCallContext context)
    {
        logger.LogInformation("Starting sign up");

        var ipAddress = context.GetHttpContext().Connection.RemoteIpAddress!;
        await identityService.InitiateSignUpAsync(
            new Core.InitiateSignUpRequest
            {
                EmailAddress = request.EmailAddress,
                IpAddress = ipAddress,
                Password = request.HasPassword ? request.Password : null,
            }, context.CancellationToken).ConfigureAwait(false);

        logger.LogInformation("Sign up initiation completed");
        return new Empty();
    }

    public override async Task<IsEmailTakenReply> IsEmailTakenAsync(IsEmailTakenRequest request,
        ServerCallContext context)
    {
        var taken = await identityService.IsEmailTakenAsync(request.EmailAddress, context.CancellationToken).ConfigureAwait(false);
        return new IsEmailTakenReply { Taken = taken };
    }

    public override async Task<Empty> VerifyAndSignUpAsync(VerifyAndSignUpRequest request, ServerCallContext context)
    {
        await identityService
            .VerifySignUpAsync(request.EmailAddress, request.VerificationCode, context.CancellationToken)
            .ConfigureAwait(false);
        return new Empty();
    }
}
