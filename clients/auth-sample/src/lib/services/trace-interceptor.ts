import type * as grpcWeb from 'grpc-web';
import { context, trace } from '@opentelemetry/api';

/**
 * TraceUnaryInterceptor injects W3C trace context into outgoing gRPC-Web requests.
 *
 * It extracts the current active span (if any) from OpenTelemetry's context,
 * builds a `traceparent` header, and attaches it to the request metadata.
 *
 * Unlike server-side gRPC, the gRPC-Web Request object does not allow in-place
 * mutation of metadata (no `setMetadata`). Instead, this interceptor clones the
 * existing metadata and passes the updated copy to the `invoker`.
 *
 * This enables distributed tracing across services by propagating trace context
 * through gRPC-Web calls.
 */
class TraceUnaryInterceptor<TReq, TRes> implements grpcWeb.UnaryInterceptor<TReq, TRes> {
    intercept(
        request: grpcWeb.Request<TReq, TRes>,
        invoker: (
            request: grpcWeb.Request<TReq, TRes>,
            metadata: grpcWeb.Metadata
        ) => Promise<grpcWeb.UnaryResponse<TReq, TRes>>
    ): Promise<grpcWeb.UnaryResponse<TReq, TRes>> {
        const original = request.getMetadata() || {};
        const metadata: grpcWeb.Metadata = {};

        // Copy only string values
        for (const [key, value] of Object.entries(original)) {
            metadata[key] = String(value);
        }

        try {
            const activeSpan = trace.getSpan(context.active());
            if (activeSpan) {
                const spanContext = activeSpan.spanContext();
                if (spanContext?.traceId && spanContext?.spanId) {
                    metadata['traceparent'] = `00-${spanContext.traceId}-${spanContext.spanId}-${spanContext.traceFlags
                        .toString(16)
                        .padStart(2, '0')}`;
                }
            }
        } catch {
            // noop
        }

        return invoker(request, metadata);
    }
}

export function createTraceUnaryInterceptor(): grpcWeb.UnaryInterceptor<unknown, unknown> {
  return new TraceUnaryInterceptor();
}


