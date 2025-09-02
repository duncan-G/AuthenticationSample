namespace AuthSample.Auth.Core.Identity;

public readonly record struct SignUpAvailability(AvailabilityStatus Status, Guid? UserId);
