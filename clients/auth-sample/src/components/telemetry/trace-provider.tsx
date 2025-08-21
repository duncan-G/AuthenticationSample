"use client";

import { useEffect } from "react";
import { initWebTelemetry } from "@/lib/telemetry";

export default function TraceProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    initWebTelemetry("auth-sample-web");
  }, []);
  return <>{children}</>;
}


