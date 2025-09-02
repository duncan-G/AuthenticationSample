import {WorkflowHandle} from "@/lib/workflows";
import { ErrorCodes, KnownErrorCode } from "./error-codes";

export const friendlyMessageFor: Record<KnownErrorCode, string> = {
    [ErrorCodes.MissingParameter]: "A required parameter is missing.",
    [ErrorCodes.InvalidParameter]: "An invalid parameter was provided.",
    [ErrorCodes.InvalidLength]: "An invalid length was provided.",
    [ErrorCodes.DuplicateEmail]: "An account with this email already exists.",
    [ErrorCodes.UserNotFound]: "We couldn't find an account with that email.",
    [ErrorCodes.VerificationCodeMismatch]: "That code doesn't look right. Please try again.",
    [ErrorCodes.VerificationCodeExpired]: "That code has expired. Request a new one to continue.",
    [ErrorCodes.VerificationAttemptsExceeded]:
        "You've entered too many incorrect codes. Please request a new code later.",
    [ErrorCodes.VerificationCodeDeliveryFailed]:
        "We couldn't send a verification code. Please try again later.",
    [ErrorCodes.ResourceExhausted]: "You've reached the maximum number of attempts. Please wait a few minutes before trying again.",
    [ErrorCodes.Unexpected]: "Something went wrong. Please try again in a moment.",
}


/**
 * Extract an API error from a standard shape:
 * {
 *   code: string | number,
 *   message: string,
 *   metadata: { "error-code"?: string, ... }
 * }
 */
const extractApiError = (err: unknown): { code?: string; serverMessage?: string } => {
    if (!err || typeof err !== "object") return {}

    const anyErr = err as {
        code?: string | number
        message?: string
        metadata?: Record<string, unknown>
    }

    // Prefer error-code from metadata
    const metaCode = anyErr.metadata?.["error-code"]
    const code =
        typeof metaCode === "string"
            ? metaCode
            : typeof anyErr.code === "string"
                ? anyErr.code
                : typeof anyErr.code === "number"
                    ? String(anyErr.code)
                    : undefined

    const serverMessage =
        typeof anyErr.message === "string" ? anyErr.message : undefined

    return { code, serverMessage }
}

export const handleApiError = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>
) => {
    const { code, serverMessage } = extractApiError(err)

    // Telemetry/logging (keep server message for developers; don't show raw to users)
    console.error("API error", { code, serverMessage, err })

    const friendly =
        (code && (friendlyMessageFor as Record<string, string>)[code]) ||
        friendlyMessageFor[ErrorCodes.Unexpected]

    // Mark workflow step (use code if present, otherwise UNKNOWN)
    step?.fail(code ?? "UNKNOWN", serverMessage ?? friendly)

    // Update UI
    setErrorMessage(friendly)
}
