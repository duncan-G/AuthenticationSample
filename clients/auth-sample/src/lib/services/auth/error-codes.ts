export const AuthErrorCodes = {
    DuplicateEmail: "1001",
    UserNotFound: "1002",
    VerificationCodeMismatch: "2001",
    VerificationCodeExpired: "2002",
    VerificationAttemptsExceeded: "2003",
    VerificationCodeDeliveryFailed: "2004",
    Unexpected: "9999",
} as const

export type KnownAuthErrorCode = (typeof AuthErrorCodes)[keyof typeof AuthErrorCodes]
