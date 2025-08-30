"use client";

import { context, Span, SpanKind, SpanStatusCode, trace } from "@opentelemetry/api";
import type { Attributes } from "@opentelemetry/api";
import { getTracer } from "@/lib/telemetry";
import type { WorkflowHandle, StepHandle } from "./types";

type WorkflowSpanBag = {
  workflowSpan: Span;
  attempts: Record<string, number>;
};

export function startWorkflow(name: string, version: string, attrs?: Record<string, unknown>): WorkflowHandle {
  const tracer = getTracer("workflow");

  const workflowSpan = tracer.startSpan(
    `workflow.${name}`,
    {
      kind: SpanKind.CLIENT,
      attributes: {
        "workflow.name": name,
        "workflow.version": version,
        ...attrs,
      },
    }
  );

  const bag: WorkflowSpanBag = { workflowSpan, attempts: {} };

  const handle: WorkflowHandle = {
    id: workflowSpan.spanContext().spanId,
    name,
    version,
    startStep: (stepName: string) => {
      const attempt = (bag.attempts[stepName] ?? 0) + 1;
      bag.attempts[stepName] = attempt;

      const stepSpan = tracer.startSpan(
        `step.${name}.${stepName}`,
        {
          kind: SpanKind.CLIENT,
          attributes: {
            "workflow.name": name,
            "workflow.version": version,
            "step.name": stepName,
            "step.attempt": attempt,
          },
        },
        trace.setSpan(context.active(), bag.workflowSpan)
      );

      const stepHandle: StepHandle = {
        name: stepName,
        attempt,
        run: async <T>(fn: () => Promise<T> | T): Promise<T> => {
          return await context.with(trace.setSpan(context.active(), stepSpan), async () => {
            return await fn();
          });
        },
        succeed: (stepAttrs) => {
          if (stepAttrs) {
            for (const [k, v] of Object.entries(stepAttrs)) {
              stepSpan.setAttribute(`step.attr.${k}` as string, v as unknown as string);
            }
          }
          stepSpan.setStatus({ code: SpanStatusCode.OK });
          stepSpan.end();
        },
        fail: (code, message, stepAttrs) => {
          if (stepAttrs) {
            for (const [k, v] of Object.entries(stepAttrs)) {
              stepSpan.setAttribute(`step.attr.${k}` as string, v as unknown as string);
            }
          }
          if (message) {
            stepSpan.recordException(new Error(message));
          } else {
            stepSpan.recordException({ name: code, message: code } as unknown as Error);
          }
          stepSpan.setAttribute("error.code", code);
          stepSpan.setStatus({ code: SpanStatusCode.ERROR, message: message ?? code });
          stepSpan.end();
        },
        event: (eventName, eventAttrs) => {
          stepSpan.addEvent(eventName, eventAttrs as Attributes);
        },
      };

      stepSpan.addEvent("step.started", { "step.name": stepName, "step.attempt": attempt });

      return stepHandle;
    },
    succeed: () => {
      workflowSpan.setStatus({ code: SpanStatusCode.OK });
      workflowSpan.end();
    },
    fail: (code, message) => {
      if (message) {
        workflowSpan.recordException(new Error(message));
      } else {
        workflowSpan.recordException({ name: code, message: code } as unknown as Error);
      }
      workflowSpan.setAttribute("error.code", code);
      workflowSpan.setStatus({ code: SpanStatusCode.ERROR, message: message ?? code });
      workflowSpan.end();
    },
    event: (eventName, eventAttrs) => {
      workflowSpan.addEvent(eventName, eventAttrs as Attributes);
    },
  };

  workflowSpan.addEvent("workflow.started", { "workflow.name": name });

  return handle;
}


