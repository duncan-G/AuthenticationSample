using AuthSample.Api.RateLimiting;
using AuthSample.Auth.Core;
using AuthSample.Auth.Core.Identity;
using AuthSample.Auth.Grpc.Protos;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using InitiateSignUpRequest = AuthSample.Auth.Grpc.Protos.InitiateSignUpRequest;
using SignUpStep = AuthSample.Auth.Grpc.Protos.SignUpStep;

namespace AuthSample.Auth.Grpc.Services;

public class SignUpManager(
    IIdentityService identityService,
    ILogger<SignUpManager> logger) : Protos.SignUpManager.SignUpManagerBase
{
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(InitiateSignUpRequest request, ServerCallContext context)
    {
        var httpContext = context.GetHttpContext();
        await httpContext.EnforceFixedByEmailAsync(request.EmailAddress, 3600, 15, cancellationToken: context.CancellationToken).ConfigureAwait(false);

        logger.LogInformation("Starting sign up");
        var ipAddress = httpContext.Connection.RemoteIpAddress!;
        var nextStep = await identityService.InitiateSignUpAsync(
            new Core.Identity.InitiateSignUpRequest
            {
                EmailAddress = request.EmailAddress,
                IpAddress = ipAddress,
                RequirePassword = request.RequirePassword,
                Password = request.HasPassword ? request.Password : null,
            }, context.CancellationToken).ConfigureAwait(false);

        logger.LogInformation("Sign up initiation completed");

        return new InitiateSignUpResponse { NextStep = (SignUpStep)nextStep };
    }

    public override async Task<Empty> VerifyAndSignUpAsync(VerifyAndSignUpRequest request, ServerCallContext context)
    {
        await context.GetHttpContext().EnforceFixedByEmailAsync(request.EmailAddress, 3600, 5, cancellationToken: context.CancellationToken).ConfigureAwait(false);

        logger.LogInformation("Verifying sign up");
        await identityService
            .VerifySignUpAndSignInAsync(request.EmailAddress, request.VerificationCode, context.CancellationToken)
            .ConfigureAwait(false);
        return new Empty();
    }
}
