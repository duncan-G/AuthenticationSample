import type { Configuration } from "@vercel/otel";
import { registerOTel } from "@vercel/otel";

function initServerTelemetry() {
  const config: Configuration = {
    serviceName: "auth-sample-web-server",
    instrumentationConfig: {
      fetch: {
        ignoreUrls: [
          // Ignore the Vercel Telemetry endpoint
          /^https:\/\/telemetry\.nextjs\.org/,

          // Ignore common static asset extensions
          /\.(png|jpg|jpeg|gif|svg|css|js|map|woff|woff2|eot|ttf|json|txt|webmanifest)$/,

          // Ignore the Next.js static assets
          /\/(_next)\//,

          // Ignore the favicon
          /favicon\.ico$/,
        ],
        propagateContextUrls: [/^https:\/\/localhost:\d+/],
        dontPropagateContextUrls: [/no-propagation\=1/],
      },
    },
  };

  registerOTel(config);
}


export function register() {
  initServerTelemetry();
}
  