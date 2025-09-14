import { trace, SpanStatusCode, context, type Span, type Context } from "@opentelemetry/api";
import { toTraceparent } from "./trace-utils";

/**
 * Constants for gRPC-Web / auth handling.
 */
const GRPC_STATUS_OK = "0";
const GRPC_UNAUTHENTICATED = 16;
const GRPC_PERMISSION_DENIED = 7;
const DEFAULT_TIMEOUT_MS = 3000;

/**
 * Builds a properly formatted gRPC-Web body for google.protobuf.Empty.
 * google.protobuf.Empty => 0 bytes; gRPC-Web prefix is 5 bytes.
 */
function buildGrpcWebEmptyBody(): Uint8Array {
  const body = new Uint8Array(5);
  // body[0] = 0 means "no compression"
  // body[1..4] = 32-bit big-endian length (0 for Empty)
  body[0] = 0;
  body[1] = 0;
  body[2] = 0;
  body[3] = 0;
  body[4] = 0;
  return body;
}

/**
 * Creates base headers for a gRPC-Web POST and injects trace context if present.
 */
function makeGrpcWebHeaders(span: Span, extra?: Record<string, string>): Record<string, string> {
  const headers: Record<string, string> = {
    "Content-Type": "application/grpc-web+proto",
    "grpc-web": "1",
    Accept: "application/grpc-web+proto",
    ...(extra ?? {}),
  };

  const sc = span.spanContext();
  if (sc.traceId && sc.spanId) {
    headers["traceparent"] = toTraceparent(sc);
    const ts = sc.traceState?.serialize();
    if (ts) headers["tracestate"] = ts;
  }

  return headers;
}

/**
 * Reads gRPC-Web status from response headers.
 */
function readGrpcStatus(res: Response): { code: number | null; message: string | null } {
  const status = res.headers.get("grpc-status");
  const message = res.headers.get("grpc-message");
  return { code: status == null ? null : Number.parseInt(status, 10), message };
}

/**
 * Runs an async fn with a timeout using AbortController.
 */
async function withTimeout<T>(ms: number, fn: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), ms);
  try {
    return await fn(ac.signal);
  } finally {
    clearTimeout(t);
  }
}

/**
 * Makes a gRPC-Web call to check user authentication.
 * Returns true when authenticated, false when explicitly unauthenticated/denied.
 * Throws on other gRPC errors or network issues.
 */
export type AuthCheckResult = {
  isAuthenticated: boolean;
  setCookies: string[];
};

function extractSetCookies(res: Response): string[] {
  const cookies: string[] = [];
  // Iterate all headers to capture multiple Set-Cookie values
  res.headers.forEach((value, key) => {
    if (key.toLowerCase() === "set-cookie" && value) {
      cookies.push(value);
    }
  });
  return cookies;
}

export async function checkAuthentication(
  authServiceUrl: string | undefined,
  parentSpan?: Span,
  additionalMetadata?: Record<string, string>,
): Promise<AuthCheckResult> {
  const tracer = trace.getTracer("middleware");

  // If a parent is provided, bind the new span to that context.
  const parentCtx: Context | undefined = parentSpan ? trace.setSpan(context.active(), parentSpan) : undefined;
  const span = tracer.startSpan("auth.check", undefined, parentCtx);
    if (!authServiceUrl) {
        throw new Error("authServiceUrl is not set");
    }

  try {
    const grpcWebUrl = `${authServiceUrl}/auth.AuthorizationService/Check`;
    const headers = makeGrpcWebHeaders(span, additionalMetadata);
    const body = buildGrpcWebEmptyBody();

    const activeCtx = trace.setSpan(context.active(), span);
    const response = await context.with(activeCtx, () =>
      withTimeout(DEFAULT_TIMEOUT_MS, (signal) =>
        fetch(grpcWebUrl, { method: "POST", headers, body, signal }),
      ),
    );
    const setCookies = extractSetCookies(response);

    // Prefer explicit gRPC status from headers; fall back to HTTP status when missing.
    const { code, message } = readGrpcStatus(response);

    if (code != null) {
      if (String(code) !== GRPC_STATUS_OK) {
        if (code === GRPC_UNAUTHENTICATED || code === GRPC_PERMISSION_DENIED) {
          span.setAttribute("auth.check.success", false);
          return { isAuthenticated: false, setCookies };
        }
        throw new Error(`gRPC error: ${code}${message ? ` - ${message}` : ""}`);
      }
      // gRPC status OK
      span.setAttribute("auth.check.success", true);
      return { isAuthenticated: true, setCookies };
    }

    if (response.status >= 400) {
        const message = response.statusText;
        throw new Error(message);
    }

    // No gRPC status header; rely on HTTP status.
    const ok = response.ok;
    span.setAttribute("auth.check.success", ok);
    return { isAuthenticated: ok, setCookies };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    span.recordException(err as Error);
    span.setStatus({ code: SpanStatusCode.ERROR, message });
    span.setAttribute("auth.check.success", false);
    throw err;
  } finally {
    span.end();
  }
}
