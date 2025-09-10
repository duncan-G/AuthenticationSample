import { context, trace } from "@opentelemetry/api";

/**
 * Returns a W3C traceparent string (version-traceId-spanId-flags)
 * from the active server span if available, otherwise null.
 */
export function getTraceparentFromActiveSpan(): string | null {
  try {
    const activeSpan = trace.getSpan(context.active());
    if (!activeSpan) return null;
    const sc = activeSpan.spanContext();
    if (!sc.traceId || !sc.spanId) return null;
    const sampled = (sc.traceFlags & 0x01) === 0x01 ? "01" : "00";
    return `00-${sc.traceId}-${sc.spanId}-${sampled}`;
  } catch {
    return null;
  }
}


