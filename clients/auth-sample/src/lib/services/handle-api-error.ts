import { WorkflowHandle } from "@/lib/workflows";
import { ErrorCodes, KnownErrorCode } from "./error-codes";

export const friendlyMessageFor: Record<KnownErrorCode, string> = {
    [ErrorCodes.MissingParameter]: "A required parameter is missing.",
    [ErrorCodes.InvalidParameter]: "An invalid parameter was provided.",
    [ErrorCodes.InvalidLength]: "An invalid length was provided.",
    [ErrorCodes.DuplicateEmail]: "This email is already in use.",
    [ErrorCodes.UserNotFound]: "We couldn't find an account with that email.",
    [ErrorCodes.VerificationCodeMismatch]: "That code doesn't look right. Please try again.",
    [ErrorCodes.VerificationCodeExpired]: "That code has expired. Request a new one to continue.",
    [ErrorCodes.VerificationAttemptsExceeded]:
        "You've entered too many incorrect codes. Please request a new code later.",
    [ErrorCodes.VerificationCodeDeliveryFailed]:
        "We couldn't send a verification code. Please try again later.",
    [ErrorCodes.MaximumUsersReached]: "We've reached our user limit. Please try again later.",
    [ErrorCodes.ResourceExhausted]:
        "You've reached the maximum number of resend attempts. Please wait before trying again.",
    [ErrorCodes.Unexpected]: "Something went wrong. Please try again in a moment.",
};

// ---- Utilities ----

type ApiErrorInfo = {
    code?: string;
    serverMessage?: string;
    retryAfterSeconds?: number;
};

const extractApiError = (err: unknown): ApiErrorInfo => {
    if (!err || typeof err !== "object") return {};

    const anyErr = err as {
        code?: string | number;
        message?: string;
        metadata?: Record<string, unknown>;
    };

    const metaCode = anyErr.metadata?.["error-code"];
    const code =
        typeof metaCode === "string"
            ? metaCode
            : typeof anyErr.code === "string"
                ? anyErr.code
                : typeof anyErr.code === "number"
                    ? String(anyErr.code)
                    : undefined;

    const serverMessage = typeof anyErr.message === "string" ? anyErr.message : undefined;

    const retryAfterMeta =
        anyErr.metadata?.["retry-after-seconds"] ||
        anyErr.metadata?.["x-retry-after-seconds"];
    const retryAfterSeconds =
        typeof retryAfterMeta === "string" ? parseInt(retryAfterMeta, 10) : undefined;

    return { code, serverMessage, retryAfterSeconds };
};

const resolveFriendlyMessage = (code?: string): string => {
    if (code && (friendlyMessageFor as Record<string, string>)[code]) {
        return (friendlyMessageFor as Record<string, string>)[code];
    }
    return friendlyMessageFor[ErrorCodes.Unexpected];
};

const getRetryAfterMinutes = ({
    retryAfterSeconds,
    serverMessage,
}: Pick<ApiErrorInfo, "retryAfterSeconds" | "serverMessage">): number | undefined => {
    if (retryAfterSeconds && retryAfterSeconds > 0) return Math.ceil(retryAfterSeconds / 60);
    const m = serverMessage?.match(/(\d+)\s*minutes?/i);
    return m ? parseInt(m[1], 10) : undefined;
};

// ---- Public APIs ----

export const handleApiError = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>
) => {
    const { code, serverMessage } = extractApiError(err);

    // Telemetry
    console.error("API error", { code, serverMessage, err });

    const friendly = resolveFriendlyMessage(code);
    step?.fail(code ?? "UNKNOWN", friendly);
    setErrorMessage(friendly);
};

/**
 * Same as handleApiError, but lets callers hook rate limit info.
 * - Triggers on ErrorCodes.ResourceExhausted only.
 * - Calls onRateLimitExceeded with a best-effort minutes estimate from metadata or server message.
 * - Optionally override the displayed friendly message for this case via rateLimitMessage.
 */
export const handleApiErrorWithRateLimit = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>,
    onRateLimitExceeded?: (retryAfterMinutes?: number) => void,
    {
        rateLimitMessage = "You've reached the maximum number of resend attempts (5 per hour). Please wait before trying again.",
    }: { rateLimitMessage?: string } = {}
) => {
    const { code, serverMessage, retryAfterSeconds } = extractApiError(err);

    // Telemetry
    console.error("API error (rate-limit aware)", {
        code,
        serverMessage,
        retryAfterSeconds,
        err,
    });

    let friendly = resolveFriendlyMessage(code);

    if (code === ErrorCodes.ResourceExhausted) {
        friendly = rateLimitMessage;
        onRateLimitExceeded?.(getRetryAfterMinutes({ retryAfterSeconds, serverMessage }));
    }

    step?.fail(code ?? "UNKNOWN", friendly);
    setErrorMessage(friendly);
};

// Legacy alias for backward compatibility
export const handleResendApiError = (
    err: unknown,
    setErrorMessage: (msg?: string) => void,
    step?: ReturnType<WorkflowHandle["startStep"]>,
    onRateLimitExceeded?: (retryAfterMinutes?: number) => void
) => {
    return handleApiErrorWithRateLimit(err, setErrorMessage, step, onRateLimitExceeded);
};