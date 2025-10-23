namespace AuthSample.Auth.Core.Identity;

public readonly record struct VerifySignUpRequest(string EmailAddress, string VerificationCode);
