"use client";

import React, { createContext, useContext, useEffect, useMemo, useRef } from "react";
import { initWebTelemetry } from "@/lib/telemetry";
import { startWorkflow } from "./start-workflow";
import type { WorkflowHandle, StepHandle } from "./types";

type Ctx = {
  start: (name: string, version: string, attrs?: Record<string, unknown>) => WorkflowHandle;
};

const WorkflowCtx = createContext<Ctx | null>(null);

export function WorkflowProvider({
  children,
  serviceName = "auth-sample-web",
}: {
  children: React.ReactNode;
  serviceName?: string;
}) {
  // Ensure telemetry is initialized before any spans are created by children
  // This avoids creating non-recording root spans during first render
  initWebTelemetry(serviceName);

  const value = useMemo<Ctx>(() => ({
    start: (name, version, attrs) => startWorkflow(name, version, attrs),
  }), []);

  return <WorkflowCtx.Provider value={value}>{children}</WorkflowCtx.Provider>;
}

export function useWorkflow(name: string, version: string, attrs?: Record<string, unknown>) {
  const ctx = useContext(WorkflowCtx);
  if (!ctx) throw new Error("WorkflowProvider missing");
  const ref = useRef<WorkflowHandle | null>(null);

  if (!ref.current) {
    ref.current = ctx.start(name, version, attrs);
  }

  useEffect(() => {
    return () => {
      ref.current?.event("component.unmounted");
    };
  }, []);

  return ref.current!;
}

export function useStep(workflow: WorkflowHandle, name: string, deps: unknown[] = []) {
  const ref = useRef<StepHandle | null>(null);

  useEffect(() => {
    ref.current = workflow.startStep(name);
    return () => {
      if (ref.current) {
        ref.current.fail?.("STEP_ABANDONED", `Step '${name}' ended without terminal status`);
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return {
    succeed: (stepAttrs?: Record<string, unknown>) => ref.current?.succeed(stepAttrs),
    fail: (code: string, message?: string, stepAttrs?: Record<string, unknown>) => ref.current?.fail(code, message, stepAttrs),
    event: (eventName: string, stepAttrs?: Record<string, unknown>) => ref.current?.event(eventName, stepAttrs),
  };
}


