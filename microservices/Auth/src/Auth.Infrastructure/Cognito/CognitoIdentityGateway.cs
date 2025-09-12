using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Amazon.CognitoIdentityProvider;
using Amazon.CognitoIdentityProvider.Model;
using Amazon.Runtime;
using AuthSample.Auth.Core.Exceptions;
using AuthSample.Auth.Core.Identity;
using AuthSample.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace AuthSample.Auth.Infrastructure.Cognito;

public sealed class CognitoIdentityGateway(
    ILogger<CognitoIdentityGateway> logger,
    IOptions<CognitoOptions> cognitoOptions,
    IAmazonCognitoIdentityProvider cognitoIdentityProvider) : IIdentityGateway
{
    private static readonly ActivitySource ActivitySource = new("AuthSample.Auth.Infrastructure");
    private const string ConfirmedUserErrorMessage = "User cannot be confirmed. Current status is CONFIRMED";

    public async Task<SignUpAvailability> GetSignUpAvailabilityAsync(string email,
        CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(GetSignUpAvailabilityAsync)}");

        activity?.SetTag("aws.cognito.operation", "AdminGetUser");
        activity?.SetTag("enduser.id", MaskEmail(email));

        var request = new AdminGetUserRequest { Username = email, UserPoolId = cognitoOptions.Value.UserPoolId };

        try
        {
            var response = await cognitoIdentityProvider.AdminGetUserAsync(request, cancellationToken)
                .ConfigureAwait(false);
            var userIdString = response.UserAttributes.FirstOrDefault(a => a.Name == "sub")?.Value;
            if (!Guid.TryParse(userIdString, out var userId))
            {
                activity?.SetStatus(ActivityStatusCode.Error, "Invalid Cognito user sub format");
                throw new CognitoOperationFailedException(
                    nameof(cognitoIdentityProvider.AdminGetUserAsync),
                    message:
                    $"Cognito user found, but their 'sub' attribute ('{userIdString}') could not be parsed as a Guid.");
            }

            var status = response.UserStatus == UserStatusType.UNCONFIRMED
                ? AvailabilityStatus.PendingConfirm
                : AvailabilityStatus.AlreadySignedUp;

            activity?.SetTag("user.exists", true);
            activity?.SetTag("user.status", response.UserStatus);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);
            return new SignUpAvailability(status, userId);
        }
        catch (UserNotFoundException)
        {
            activity?.SetTag("user.exists", false);
            return new SignUpAvailability(AvailabilityStatus.NewUser, null);
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.AdminGetUserAsync),
                null,
                "Failed to initiate sign up",
                ex);
        }
    }

    public async Task<Guid> InitiateSignUpAsync(InitiateSignUpRequest request,
        CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(InitiateSignUpAsync)}");

        activity?.SetTag("aws.cognito.operation", "SignUp");
        activity?.SetTag("enduser.id", MaskEmail(request.EmailAddress));
        activity?.SetTag("client.address", request.IpAddress.ToString());

        var signUpRequest = new SignUpRequest
        {
            ClientId = cognitoOptions.Value.ClientId,
            Username = request.EmailAddress,
            UserAttributes =
            [
                new AttributeType { Name = "email", Value = request.EmailAddress }
            ],
            UserContextData = new UserContextDataType { IpAddress = request.IpAddress.ToString() },
            SecretHash = ComputeSecretHash(request.EmailAddress)
        };
        if (!string.IsNullOrWhiteSpace(request.Password))
        {
            signUpRequest.Password = request.Password;
        }

        try
        {
            var response = await cognitoIdentityProvider.SignUpAsync(signUpRequest, cancellationToken).ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);
            activity?.SetTag("cognito.user_sub", response.UserSub);
            activity?.AddEvent(new ActivityEvent(
                "verification.code_sent",
                tags: new ActivityTagsCollection
                {
                    ["message.delivery.mode"] = response.CodeDeliveryDetails.DeliveryMedium?.Value,
                    ["message.delivery.destination"] = Mask(response.CodeDeliveryDetails.Destination)
                }));

            logger.LogInformation("Verification code sent");
            return Guid.Parse(response.UserSub);
        }
        catch (CodeDeliveryFailureException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogError(ex, "Cognito code delivery failed");
            throw new VerificationCodeDeliveryFailedException();
        }
        catch (UsernameExistsException)
        {
            activity?.SetTag("business.duplicate_email", true);
            throw new DuplicateEmailException();
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.SignUpAsync),
                null,
                "Failed to initiate sign up",
                ex);
        }
    }

    public async Task<string> VerifySignUpAsync(VerifySignUpRequest request, CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(VerifySignUpAsync)}");

        activity?.SetTag("aws.cognito.operation", "ConfirmSignUp");
        activity?.SetTag("enduser.id", MaskEmail(request.EmailAddress));

        var signUpRequest = new ConfirmSignUpRequest
        {
            ClientId = cognitoOptions.Value.ClientId,
            ConfirmationCode = request.VerificationCode,
            Username = request.EmailAddress,
            SecretHash = ComputeSecretHash(request.EmailAddress)
        };

        try
        {
            var response = await cognitoIdentityProvider.ConfirmSignUpAsync(signUpRequest, cancellationToken)
                .ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);
            return response.Session;
        }
        catch (AliasExistsException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Cognito alias exists during confirmation");
            throw new DuplicateEmailException();
        }
        catch (CodeMismatchException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Verification code mismatch");
            throw new VerificationCodeMismatchException();
        }
        catch (ExpiredCodeException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Verification code expired");
            throw new VerificationCodeExpiredException();
        }
        catch (LimitExceededException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Verification attempts limit exceeded");
            throw new VerificationAttemptsExceededException();
        }
        catch (TooManyRequestsException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Verification too many requests");
            throw new VerificationAttemptsExceededException();
        }
        catch (TooManyFailedAttemptsException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "Verification too many failed attempts");
            throw new VerificationAttemptsExceededException();
        }
        catch (UserNotFoundException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "User not found during verification");
            throw new UserWithEmailNotFoundException();
        }
        catch (NotAuthorizedException ex) when (ex.Message == ConfirmedUserErrorMessage)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogWarning(ex, "User already confirmed");
            throw new UserAlreadyConfirmedException();
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.ConfirmSignUpAsync),
                null,
                "Failed to verify sign up.",
                ex);
        }
    }

    public async Task ResendSignUpVerificationAsync(
        string emailAddress,
        IPAddress ipAddress,
        CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(ResendSignUpVerificationAsync)}");

        activity?.SetTag("aws.cognito.operation", "ResendConfirmationCode");
        activity?.SetTag("enduser.id", MaskEmail(emailAddress));
        activity?.SetTag("client.address", ipAddress.ToString());

        var resendRequest = new ResendConfirmationCodeRequest
        {
            ClientId = cognitoOptions.Value.ClientId,
            Username = emailAddress,
            UserContextData = new UserContextDataType { IpAddress = ipAddress.ToString() },
            SecretHash = ComputeSecretHash(emailAddress)
        };

        try
        {
            var response = await cognitoIdentityProvider.ResendConfirmationCodeAsync(resendRequest, cancellationToken)
                .ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);
            activity?.AddEvent(new ActivityEvent(
                "verification.code_sent",
                tags: new ActivityTagsCollection
                {
                    ["message.delivery.mode"] = response.CodeDeliveryDetails.DeliveryMedium?.Value,
                    ["message.delivery.destination"] = Mask(response.CodeDeliveryDetails.Destination)
                }));
            logger.LogInformation("Verification code sent");
        }
        catch (CodeDeliveryFailureException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogError(ex, "Cognito code delivery failed");
            throw new VerificationCodeDeliveryFailedException();
        }
        catch (TooManyRequestsException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogError(ex, "Cognito code delivery throttled");
            throw new VerificationCodeDeliveryTooSoonException();
        }
        catch (LimitExceededException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogError(ex, "Cognito code delivery throttled");
            throw new VerificationCodeDeliveryTooSoonException();
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.ResendConfirmationCodeAsync),
                null,
                "Failed to send verification email.",
                ex);
        }
    }

    public async Task ConfirmUserAsync(string emailAddress, CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(ConfirmUserAsync)}");

        activity?.SetTag("aws.cognito.operation", "AdminConfirmUser");
        activity?.SetTag("enduser.id", MaskEmail(emailAddress));

        var confirmSignUpRequest = new AdminConfirmSignUpRequest
        {
            UserPoolId = cognitoOptions.Value.UserPoolId, Username = emailAddress,
        };

        try
        {
            var response = await cognitoIdentityProvider.AdminConfirmSignUpAsync(confirmSignUpRequest, cancellationToken).ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.AdminSetUserPasswordAsync),
                null,
                "Failed to confirm user.",
                ex);
        }
    }

    public async Task<SessionData> InitiateAuthAsync(string emailAddress, string sessionId, CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(InitiateAuthAsync)}");

        activity?.SetTag("aws.cognito.operation", "InitiateAuth");

        var initiateAuthRequest = new InitiateAuthRequest
        {
            Session = sessionId,
            AuthFlow = AuthFlowType.USER_AUTH,
            ClientId = cognitoOptions.Value.ClientId,
            AuthParameters = new Dictionary<string, string>
            {
                { "USERNAME", emailAddress  },
                { "SECRET_HASH", ComputeSecretHash(emailAddress) }
            },
        };

        try
        {
            var now = DateTime.UtcNow;
            var response = await cognitoIdentityProvider.InitiateAuthAsync(initiateAuthRequest, cancellationToken)
                .ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);

            var idJwt = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler()
                .ReadJwtToken(response.AuthenticationResult.IdToken);
            var cognitoUsername = idJwt.Claims.First(c => c.Type == "cognito:username").Value;
            return new SessionData(
                now,
                response.AuthenticationResult.AccessToken,
                response.AuthenticationResult.IdToken,
                now.AddSeconds((double)response.AuthenticationResult.ExpiresIn!),
                response.AuthenticationResult.RefreshToken,
                now.AddDays(cognitoOptions.Value.RefreshTokenExpirationDays),
                cognitoUsername,
                emailAddress);
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.AdminSetUserPasswordAsync),
                null,
                "Failed to initiate authentication.",
                ex);
        }
    }

    public async Task<SessionData> RefreshSessionAsync(RefreshTokenRecord refreshTokenRecord, CancellationToken cancellationToken = default)
    {
        using var activity = ActivitySource.StartActivity(
            $"{nameof(CognitoIdentityGateway)}.{nameof(RefreshSessionAsync)}");

        activity?.SetTag("aws.cognito.operation", "InitiateAuth");

        var initiateAuthRequest = new InitiateAuthRequest
        {
            AuthFlow = AuthFlowType.REFRESH_TOKEN_AUTH,
            ClientId = cognitoOptions.Value.ClientId,
            AuthParameters = new Dictionary<string, string>
            {
                { "REFRESH_TOKEN", refreshTokenRecord.RefreshToken },
                { "SECRET_HASH", ComputeSecretHash(refreshTokenRecord.UserSub) }
            },
        };

        try
        {
            var now = DateTime.UtcNow;
            var response = await cognitoIdentityProvider.InitiateAuthAsync(initiateAuthRequest, cancellationToken)
                .ConfigureAwait(false);
            activity?.SetTag("aws.request_id", response.ResponseMetadata.RequestId);

            var idToken = response.AuthenticationResult.IdToken;
            var accessToken = response.AuthenticationResult.AccessToken;
            var expiresIn = response.AuthenticationResult.ExpiresIn ?? 3600;

            // Cognito does not always return refresh token on refresh flow; keep the same one
            return new SessionData(
                now,
                accessToken,
                idToken,
                now.AddSeconds(expiresIn),
                refreshTokenRecord.RefreshToken,
                now.AddDays(cognitoOptions.Value.RefreshTokenExpirationDays),
                refreshTokenRecord.UserSub,
                refreshTokenRecord.UserEmail);
        }
        catch (AmazonServiceException ex)
        {
            activity?.AddException(ex);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            activity?.SetTag("aws.request_id", ex.RequestId);
            throw new CognitoOperationFailedException(
                nameof(cognitoIdentityProvider.InitiateAuthAsync),
                null,
                "Failed to refresh authentication.",
                ex);
        }
    }

    // https://docs.aws.amazon.com/cognito/latest/developerguide/signing-up-users-in-your-app.html#cognito-user-pools-computing-secret-hash
    private string ComputeSecretHash(string email)
    {
        var keyBytes = Encoding.UTF8.GetBytes(cognitoOptions.Value.Secret);
        using var hmac = new HMACSHA256(keyBytes);

        var messageBytes = Encoding.UTF8.GetBytes(email + cognitoOptions.Value.ClientId);
        var hashBytes = hmac.ComputeHash(messageBytes);

        return Convert.ToBase64String(hashBytes);
    }

    private static string Mask(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        if (value.Length <= 4)
        {
            return "***";
        }

        return new string('*', Math.Max(0, value.Length - 4)) + value[^4..];
    }

    private static string MaskEmail(string email)
    {
        var atIndex = email.IndexOf('@');
        if (atIndex <= 1)
        {
            return "***";
        }

        var local = email[..atIndex];
        var domain = email[(atIndex + 1)..];
        var maskedLocal = local.Length <= 2
            ? local[0] + "*"
            : local[0] + new string('*', local.Length - 2) + local[^1];
        return maskedLocal + "@" + domain;
    }
}
