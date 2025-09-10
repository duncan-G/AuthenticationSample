import { type Span } from "@opentelemetry/api";

/**
 * Converts a span context to a W3C traceparent header value
 */
export function toTraceparent(sc: ReturnType<Span["spanContext"]>): string {
    const sampled = (sc.traceFlags & 0x01) === 0x01 ? "01" : "00";
    return `00-${sc.traceId}-${sc.spanId}-${sampled}`;
}

/**
 * Injects span context into Headers object for trace propagation
 */
export function injectSpanContextHeaders(headers: Headers, span: Span): void {
    const sc = span.spanContext();
    if (!sc.traceId || !sc.spanId) return;

    headers.set("traceparent", toTraceparent(sc));
    const tracestate = sc.traceState?.serialize();
    if (tracestate) headers.set("tracestate", tracestate);
}

/**
 * Checks if incoming headers contain trace context
 */
export function hasIncomingTrace(headers: Record<string, string>): boolean {
    return Boolean(headers["traceparent"]);
}
