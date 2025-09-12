using AuthSample.Api.RateLimiting;
using AuthSample.Auth.Core.Identity;
using AuthSample.Auth.Grpc.Protos;
using Google.Protobuf.WellKnownTypes;
using Grpc.Core;
using InitiateSignUpRequest = AuthSample.Auth.Grpc.Protos.InitiateSignUpRequest;
using SignUpStep = AuthSample.Auth.Grpc.Protos.SignUpStep;

namespace AuthSample.Auth.Grpc.Services;

public class SignUpService(
    ISignUpEligibilityGuard eligibilityGuard,
    IIdentityService identityService,
    ILogger<SignUpService> logger) : Protos.SignUpService.SignUpServiceBase
{
    public override async Task<InitiateSignUpResponse> InitiateSignUpAsync(InitiateSignUpRequest request, ServerCallContext context)
    {
        await eligibilityGuard.EnforceMaxConfirmedUsersAsync().ConfigureAwait(false);

        var httpContext = context.GetHttpContext();
        await httpContext.
            EnforceFixedByEmailAsync(request.EmailAddress, 3600, 15, cancellationToken: context.CancellationToken)
            .ConfigureAwait(false);

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

    public override async Task<VerifyAndSignInResponse> VerifyAndSignInAsync(VerifyAndSignInRequest request, ServerCallContext context)
    {
        await eligibilityGuard.EnforceMaxConfirmedUsersAsync().ConfigureAwait(false);

        await context.GetHttpContext()
            .EnforceFixedByEmailAsync(request.EmailAddress, 3600, 5, cancellationToken: context.CancellationToken)
            .ConfigureAwait(false);

        logger.LogInformation("Verifying sign up");
        var clientSession = await identityService
            .VerifySignUpAndSignInAsync(request.EmailAddress, request.VerificationCode, context.CancellationToken)
            .ConfigureAwait(false);

        logger.LogInformation("Sign up completed");

        if (clientSession is not null)
        {
            var accessTokenCookie =
                $"AT_SID={clientSession.AccessTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={clientSession.AccessTokenExpiry.ToUniversalTime():R}";
            var refreshTokenCookie =
                $"RT_SID={clientSession.RefreshTokenId}; Path=/; HttpOnly; Secure; SameSite=Strict; Expires={clientSession.RefreshTokenExpiry.ToUniversalTime():R}";
            await context.WriteResponseHeadersAsync(new Metadata
            {
                { "set-cookie", accessTokenCookie }, { "set-cookie", refreshTokenCookie }
            }).ConfigureAwait(false);

            return new VerifyAndSignInResponse { NextStep = SignUpStep.RedirectRequired };
        }

        return new VerifyAndSignInResponse { NextStep = SignUpStep.SignInRequired };
    }

    public override async Task<Empty> ResendVerificationCodeAsync(ResendVerificationCodeRequest request, ServerCallContext context)
    {
        await eligibilityGuard.EnforceMaxConfirmedUsersAsync().ConfigureAwait(false);

        var httpContext = context.GetHttpContext();
        await httpContext
            .EnforceFixedByEmailAsync(request.EmailAddress, 3600, 5, cancellationToken: context.CancellationToken)
            .ConfigureAwait(false);

        logger.LogInformation("Resending verification code for {EmailAddress}", request.EmailAddress);

        var ipAddress = httpContext.Connection.RemoteIpAddress!;
        await identityService.ResendVerificationCodeAsync(request.EmailAddress, ipAddress, context.CancellationToken)
            .ConfigureAwait(false);

        logger.LogInformation("Successfully processed resend verification code request for {EmailAddress}", request.EmailAddress);
        return new Empty();
    }
}
