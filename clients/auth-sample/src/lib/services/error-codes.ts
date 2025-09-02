// This file is auto-generated. Do not edit manually.
// To regenerate, run: node scripts/development/generate_error_codes.js

export const ErrorCodes = {
    MissingParameter: "1000",
    InvalidParameter: "1001",
    InvalidLength: "1002",
    DuplicateEmail: "2000",
    UserNotFound: "2001",
    VerificationCodeMismatch: "2002",
    VerificationCodeExpired: "2003",
    VerificationAttemptsExceeded: "2004",
    VerificationCodeDeliveryFailed: "2005",
    ResourceExhausted: "9998",
    Unexpected: "9999",
} as const

export type KnownErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes]