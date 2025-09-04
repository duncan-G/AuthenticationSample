/**
 * The `register` function is a Next.js convention for running code on server startup.
 * We use it to initialize our server-side telemetry.
 * @see https://nextjs.org/docs/app/building-your-application/optimizing/instrumentation
 */
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
import { OTLPMetricExporter } from "@opentelemetry/exporter-metrics-otlp-proto";
import { PeriodicExportingMetricReader } from "@opentelemetry/sdk-metrics";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";
import { trace, SpanStatusCode } from "@opentelemetry/api";
import { CompositePropagator, W3CTraceContextPropagator } from "@opentelemetry/core";
import { B3Propagator } from "@opentelemetry/propagator-b3";

// A global variable is used to cache the initialized SDK.
// This prevents re-initialization during hot-reloads in development.
declare global {
    // eslint-disable-next-line no-var
    var otelSDK: NodeSDK | undefined;
}

/**
 * Initializes and starts the OpenTelemetry SDK for the Node.js server environment.
 */
function initServerTelemetry() {
    // Do not run in Edge runtime.
    if (process.env.NEXT_RUNTIME === "edge") {
        return;
    }

    // Do not run in client-side bundles.
    if (typeof window !== "undefined") {
        return;
    }

    // Prevent re-initialization if the SDK is already running.
    if (global.otelSDK) {
        console.log("[otel] Telemetry SDK already initialized.");
        return global.otelSDK;
    }

    // Use a server-side environment variable. NEXT_PUBLIC_* is exposed to the client.
    const otlpEndpoint = process.env.NEXT_PUBLIC_OTLP_HTTP_ENDPOINT;
    if (!otlpEndpoint) {
        console.log("[otel] OTLP endpoint is not configured. Telemetry is disabled.");
        return;
    }

    console.log(`[otel] Initializing Telemetry for service: auth-sample-web-server`);

    const traceExporter = new OTLPTraceExporter({
        url: `${otlpEndpoint}/traces`, // OTLP HTTP endpoint for traces
    });

    const metricReader = new PeriodicExportingMetricReader({
        exporter: new OTLPMetricExporter({
            url: `${otlpEndpoint}/metrics`, // OTLP HTTP endpoint for metrics
        }),
        exportIntervalMillis: 10000, // Export metrics every 10 seconds
    });

    const sdk = new NodeSDK({
        resource: resourceFromAttributes({
            [ATTR_SERVICE_NAME]: "auth-sample-server",
        }),
        traceExporter,
        metricReader,
        // Enable auto instrumentations and ensure HTTP emits Server-Timing for browser correlation
        instrumentations: [
            getNodeAutoInstrumentations(),
        ],
        // Use a composite propagator to support both W3C and B3 headers
        textMapPropagator: new CompositePropagator({
            propagators: [new W3CTraceContextPropagator(), new B3Propagator()],
        }),
    });

    // Gracefully shut down the SDK on process exit
    process.on("SIGTERM", () => {
        sdk.shutdown().then(
            () => console.log("Telemetry shutdown complete."),
            (err) => console.log("Error shutting down telemetry", err),
        ).finally(() => process.exit(0));
    });

    // Start the SDK and assign it to the global variable
    sdk.start();
    global.otelSDK = sdk;

    // Add custom global error handlers after the SDK has started
    addGlobalErrorHandlers();

    return sdk;
}

function addGlobalErrorHandlers() {
    const errorTracer = trace.getTracer('global-error-handler');

    process.on('uncaughtException', (err: Error) => {
        console.error("Caught Uncaught Exception:", err);
        const span = errorTracer.startSpan('uncaught_exception');
        span.recordException(err);
        span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
        span.end();
        // It's crucial to rethrow or exit after catching this, as the application
        // is in an undefined state.
    });

    process.on('unhandledRejection', (reason: unknown) => {
        console.error("Caught Unhandled Rejection:", reason);
        const span = errorTracer.startSpan('unhandled_promise_rejection');
        if (reason instanceof Error) {
            span.recordException(reason);
            span.setStatus({ code: SpanStatusCode.ERROR, message: reason.message });
        } else {
            span.setStatus({ code: SpanStatusCode.ERROR, message: String(reason) });
        }
        span.end();
    });
}


export function register() {
    initServerTelemetry();
}
