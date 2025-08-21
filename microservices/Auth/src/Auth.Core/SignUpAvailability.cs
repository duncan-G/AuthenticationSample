namespace AuthSample.Auth.Core;

public readonly record struct SignUpAvailability(AvailabilityStatus Status, Guid? UserId);
