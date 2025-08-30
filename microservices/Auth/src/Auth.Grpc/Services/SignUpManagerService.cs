using AuthSample.Auth.Core;
using AuthSample.Auth.Grpc.Protos;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using Microsoft.AspNetCore.RateLimiting;
using InitiateSignUpRequest = AuthSample.Auth.Grpc.Protos.InitiateSignUpRequest;
using SignUpStep = AuthSample.Auth.Grpc.Protos.SignUpStep;

namespace AuthSample.Auth.Grpc.Services;

public class SignUpManagerService(
    IIdentityService identityService,
    ILogger<SignUpManagerService> logger) : SignUpManager.SignUpManagerBase
{
    [EnableRateLimiting("initiate-signup")]
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(InitiateSignUpRequest request, ServerCallContext context)
    {
        logger.LogInformation("Starting sign up");

        var ipAddress = context.GetHttpContext().Connection.RemoteIpAddress!;
        var nextStep = await identityService.InitiateSignUpAsync(
            new Core.InitiateSignUpRequest
            {
                EmailAddress = request.EmailAddress,
                IpAddress = ipAddress,
                RequirePassword = request.RequirePassword,
                Password = request.HasPassword ? request.Password : null,
            }, context.CancellationToken).ConfigureAwait(false);

        logger.LogInformation("Sign up initiation completed");

        return new InitiateSignUpResponse { NextStep = (SignUpStep)nextStep };
    }

    [EnableRateLimiting("confirm-user")]
    public override async Task<Empty> VerifyAndSignUpAsync(VerifyAndSignUpRequest request, ServerCallContext context)
    {
        await identityService
            .VerifySignUpAndSignInAsync(request.EmailAddress, request.VerificationCode, context.CancellationToken)
            .ConfigureAwait(false);
        return new Empty();
    }
}
