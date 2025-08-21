"use client";

import { WebTracerProvider } from "@opentelemetry/sdk-trace-web";
import { registerInstrumentations } from "@opentelemetry/instrumentation";
import { FetchInstrumentation } from "@opentelemetry/instrumentation-fetch";
import { XMLHttpRequestInstrumentation } from "@opentelemetry/instrumentation-xml-http-request";
import { DocumentLoadInstrumentation } from "@opentelemetry/instrumentation-document-load";
import { ZoneContextManager } from "@opentelemetry/context-zone";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
import { BatchSpanProcessor, SpanProcessor, ReadableSpan } from "@opentelemetry/sdk-trace-base";
import { B3Propagator } from "@opentelemetry/propagator-b3";
import { W3CTraceContextPropagator } from "@opentelemetry/core";
import { CompositePropagator } from "@opentelemetry/core";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { context, trace, SpanStatusCode } from "@opentelemetry/api";
import type { Context as OtelContext, Span } from "@opentelemetry/api";
import { config } from "@/lib/config";
import { isBrowser } from "@/lib/utils";

let initialized = false;

export function initWebTelemetry(serviceName: string = "auth-sample-web") {
  if (!isBrowser() || initialized) return;

  const exporter = new OTLPTraceExporter({
    url: `${config.otlpHttpEndpoint}/traces`,
    headers: {},
  });

  // Drop OPTIONS requests from export to avoid separate traces for preflight
  class PredicateSpanProcessor implements SpanProcessor {
    private _inner: SpanProcessor;
    private _predicate: (span: ReadableSpan) => boolean;
    constructor(inner: SpanProcessor, predicate: (span: ReadableSpan) => boolean) {
      this._inner = inner;
      this._predicate = predicate;
    }
    onStart(span: Span, ctx: OtelContext) {
      const maybeHasOnStart = this._inner as unknown as { onStart?: (span: Span, ctx: OtelContext) => void };
      if (typeof maybeHasOnStart.onStart === "function") maybeHasOnStart.onStart(span, ctx);
    }
    onEnd(span: ReadableSpan) {
      if (this._predicate(span)) this._inner.onEnd(span);
    }
    shutdown() {
      return this._inner.shutdown();
    }
    forceFlush() {
      return this._inner.forceFlush();
    }
  }

  const shouldExportSpan = (span: ReadableSpan): boolean => {
    const methodAttr = span.attributes["http.request.method"] ?? span.attributes["http.method"];
    if (typeof methodAttr === "string" && methodAttr.toUpperCase() === "OPTIONS") {
      return false;
    }
    return true;
  };

  const filteredBatchProcessor = new PredicateSpanProcessor(new BatchSpanProcessor(exporter), shouldExportSpan);

  const provider = new WebTracerProvider({
    resource: resourceFromAttributes({
      "service.name": serviceName,
      "service.instance.id": serviceName,
    }),
    spanProcessors: [filteredBatchProcessor],
  });

  // Note: addSpanProcessor may not exist in some SDK versions; we configured via constructor above

  provider.register({
    contextManager: new ZoneContextManager(),
    propagator: new CompositePropagator({
      propagators: [new W3CTraceContextPropagator(), new B3Propagator()],
    }),
  });

  // Capture unhandled errors and promise rejections as error spans
  try {
    const errorTracer = trace.getTracer("errors");
    if (typeof window !== "undefined") {
      window.addEventListener("error", (event: ErrorEvent) => {
        try {
          const span = errorTracer.startSpan("unhandled_error");
          span.recordException(event.error ?? event.message);
          span.setStatus({ code: SpanStatusCode.ERROR, message: String(event.message) });
          span.end();
        } catch {}
      });
      window.addEventListener("unhandledrejection", (event: PromiseRejectionEvent) => {
        try {
          const span = errorTracer.startSpan("unhandled_promise_rejection");
          const reason = event.reason as unknown;
          const message = reason instanceof Error ? reason.message : String(reason);
          const exception = reason instanceof Error ? reason : message;
          span.recordException(exception);
          span.setStatus({ code: SpanStatusCode.ERROR, message: message });
          span.end();
        } catch {}
      });
    }
  } catch {}

  registerInstrumentations({
    instrumentations: [
      new DocumentLoadInstrumentation(),
      new FetchInstrumentation({
        propagateTraceHeaderCorsUrls: [/.*/],
        clearTimingResources: true,
        applyCustomAttributesOnSpan: (span, request, result) => {
          try {
            span.setAttribute("http.request.method", (request as Request).method);
            const res = result as Response | { response?: { status?: number } } | undefined | null;
            const status = res instanceof Response ? res.status : res?.response?.status;
            if (typeof status === "number") {
              span.setAttribute("http.response.status_code", status);
              if (status >= 400) {
                span.setStatus({ code: SpanStatusCode.ERROR });
                span.addEvent("exception", {
                  "exception.type": "HTTPError",
                  "exception.message": `HTTP ${status}`,
                  "exception.escaped": true,
                });
              }
            }
          } catch {}
        },
      }),
      new XMLHttpRequestInstrumentation({
        propagateTraceHeaderCorsUrls: [/.*/],
        applyCustomAttributesOnSpan: (span, xhr) => {
          try {
            const status = xhr.status;
            if (typeof status === "number") {
              span.setAttribute("http.response.status_code", status);
              if (status >= 400) {
                span.setStatus({ code: SpanStatusCode.ERROR });
                span.addEvent("exception", {
                  "exception.type": "HTTPError",
                  "exception.message": `HTTP ${status}`,
                  "exception.escaped": true,
                });
              }
            }
          } catch {}
        },
      }),
    ],
  });

  initialized = true;
}

export function getTracer(name: string = "web") {
  return trace.getTracer(name);
}

export function runWithTracing<T>(name: string, fn: () => Promise<T> | T) {
  const tracer = getTracer("workflow");
  const span = tracer.startSpan(name);
  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const result = await fn();
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (err: unknown) {
      if (err instanceof Error) {
        span.recordException(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      } else {
        const message = String(err);
        span.recordException(message);
        span.setStatus({ code: SpanStatusCode.ERROR, message });
      }
      throw err;
    } finally {
      span.end();
    }
  });
}


