export type WorkflowHandle = {
  id: string;
  name: string;
  version: string;
  startStep: (name: string) => StepHandle;
  succeed: () => void;
  fail: (code: string, message?: string) => void;
  event: (name: string, attrs?: Record<string, unknown>) => void;
};

export type StepHandle = {
  name: string;
  attempt: number;
  run: <T>(fn: () => Promise<T> | T) => Promise<T>;
  succeed: (attrs?: Record<string, unknown>) => void;
  fail: (code: string, message?: string, attrs?: Record<string, unknown>) => void;
  event: (name: string, attrs?: Record<string, unknown>) => void;
};


