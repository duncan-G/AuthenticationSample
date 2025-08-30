namespace AuthSample.Auth.Core;

public readonly record struct VerifySignUpRequest(string EmailAddress, string VerificationCode);
