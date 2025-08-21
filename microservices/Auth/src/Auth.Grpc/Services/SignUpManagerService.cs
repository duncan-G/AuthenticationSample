using Amazon.CognitoIdentityProvider.Model;
using AuthSample.Auth.Core;
using AuthSample.Auth.Core.Exceptions;
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

        try
        {
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
        catch (DuplicateEmailException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.DuplicateEmail },
                { "field", "email" }
            };
            throw new RpcException(new Status(StatusCode.AlreadyExists, ex.Message), metadata);
        }
        catch (VerificationCodeDeliveryFailedException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.CodeDeliveryFailed },
                { "operation", "initiate-signup" }
            };
            throw new RpcException(new Status(StatusCode.FailedPrecondition, ex.Message), metadata);
        }
        catch (CognitoOperationFailedException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.CognitoOperationFailed },
                { "operation", ex.OperationName }
            };
            throw new RpcException(new Status(StatusCode.Internal, ex.Message), metadata);
        }
        catch (Exception)
        {
            var metadata = new Metadata { { "error-code", ErrorCodes.Unexpected } };
            throw new RpcException(new Status(StatusCode.Internal, "Unexpected error"), metadata);
        }
    }

    public override async Task<IsEmailTakenReply> IsEmailTakenAsync(IsEmailTakenRequest request,
        ServerCallContext context)
    {
        var taken = await identityService.IsEmailTakenAsync(request.EmailAddress, context.CancellationToken).ConfigureAwait(false);
        return new IsEmailTakenReply { Taken = taken };
    }

    public override async Task<Empty> VerifyAndSignUpAsync(VerifyAndSignUpRequest request, ServerCallContext context)
    {
        try
        {
            await identityService.VerifySignUpAsync(request.EmailAddress, request.VerificationCode, context.CancellationToken)
                .ConfigureAwait(false);
            return new Empty();
        }
        catch (VerificationCodeMismatchException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.VerificationCodeMismatch },
                { "field", "verificationCode" }
            };
            throw new RpcException(new Status(StatusCode.InvalidArgument, ex.Message), metadata);
        }
        catch (VerificationCodeExpiredException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.VerificationCodeExpired },
                { "field", "verificationCode" }
            };
            throw new RpcException(new Status(StatusCode.FailedPrecondition, ex.Message), metadata);
        }
        catch (VerificationAttemptsExceededException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.VerificationAttemptsExceeded },
                { "operation", "verify-signup" }
            };
            throw new RpcException(new Status(StatusCode.ResourceExhausted, ex.Message), metadata);
        }
        catch (UserWithEmailNotFoundException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.UserNotFound },
                { "field", "email" }
            };
            throw new RpcException(new Status(StatusCode.NotFound, ex.Message), metadata);
        }
        catch (DuplicateEmailException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", "1001" },
                { "field", "email" }
            };
            throw new RpcException(new Status(StatusCode.AlreadyExists, ex.Message), metadata);
        }
        catch (CognitoOperationFailedException ex)
        {
            var metadata = new Metadata
            {
                { "error-code", ErrorCodes.CognitoOperationFailed },
                { "operation", ex.OperationName }
            };
            throw new RpcException(new Status(StatusCode.Internal, ex.Message), metadata);
        }
        catch (Exception ex)
        {
            var metadata = new Metadata { { "error-code", ErrorCodes.Unexpected } };
            throw new RpcException(new Status(StatusCode.Internal, "Unexpected error"), metadata);
        }
    }
}
