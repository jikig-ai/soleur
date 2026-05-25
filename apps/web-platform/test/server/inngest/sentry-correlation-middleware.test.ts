// Unit tests for the Inngest → Sentry correlation middleware.
//
// Strategy: invoke the middleware's hook chain directly (the same way
// Inngest's executor does at runtime) and assert against a fully-mocked
// @sentry/nextjs surface. No real Inngest function-run scaffold needed —
// the middleware is a pure factory.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const sentryCalls = {
  setTag: vi.fn(),
  setExtra: vi.fn(),
  addBreadcrumb: vi.fn(),
  captureException: vi.fn(),
};

vi.mock("@sentry/nextjs", () => ({
  getCurrentScope: () => ({
    setTag: (k: string, v: unknown) => {
      sentryCalls.setTag(k, v);
      return { setTag: () => ({}), setExtra: () => ({}) };
    },
    setExtra: (k: string, v: unknown) => sentryCalls.setExtra(k, v),
  }),
  addBreadcrumb: (b: unknown) => sentryCalls.addBreadcrumb(b),
  captureException: (e: unknown, opts?: unknown) =>
    sentryCalls.captureException(e, opts),
}));

beforeEach(() => {
  sentryCalls.setTag.mockReset();
  sentryCalls.setExtra.mockReset();
  sentryCalls.addBreadcrumb.mockReset();
  sentryCalls.captureException.mockReset();
});
afterEach(() => vi.restoreAllMocks());

async function runHooks(opts: {
  fnId?: string;
  runId?: string;
  eventName?: string;
  eventData?: Record<string, unknown>;
  // Final result delivered to transformOutput when `step` is absent.
  finalResult?: { error?: unknown; data?: unknown };
  // Per-step transformOutput invocations BEFORE the final one.
  steps?: Array<{
    name: string;
    op?: string;
    result: { error?: unknown; data?: unknown };
  }>;
}) {
  const { sentryCorrelationMiddleware } = await import(
    "@/server/inngest/middleware/sentry-correlation"
  );
  // InngestMiddleware exposes `.init` as a public registration entry-point.
  // The `as unknown as` is necessary because Inngest's public type is
  // generic over user-config; we drive it with a minimal shape.
  type MidLike = {
    init: () => {
      onFunctionRun: (args: {
        ctx: { runId: string; event: { name: string; data?: unknown; id?: string } };
        fn: { id: () => string };
      }) => {
        transformInput?: () => void;
        beforeMemoization?: () => void;
        afterMemoization?: () => void;
        beforeExecution?: () => void;
        afterExecution?: () => void;
        transformOutput?: (a: {
          result: { error?: unknown; data?: unknown };
          step?: { name: string; op?: string };
        }) => void;
      };
    };
  };
  const mid = sentryCorrelationMiddleware as unknown as MidLike;
  const reg = mid.init();
  const hooks = reg.onFunctionRun({
    ctx: {
      runId: opts.runId ?? "run-abc-123",
      event: {
        name: opts.eventName ?? "cron/oauth-probe.manual-trigger",
        data: opts.eventData ?? {},
        id: "evt-1",
      },
    },
    fn: { id: () => opts.fnId ?? "cron-oauth-probe" },
  });
  hooks.transformInput?.();
  hooks.beforeMemoization?.();
  hooks.afterMemoization?.();
  hooks.beforeExecution?.();
  for (const s of opts.steps ?? []) {
    hooks.transformOutput?.({
      result: s.result,
      step: { name: s.name, op: s.op },
    });
  }
  hooks.afterExecution?.();
  if (opts.finalResult !== undefined) {
    hooks.transformOutput?.({ result: opts.finalResult });
  }
}

describe("sentry-correlation middleware", () => {
  it("tags scope with fn_id, run_id, event_name on transformInput", async () => {
    await runHooks({
      fnId: "cron-oauth-probe",
      runId: "run-42",
      eventName: "cron/oauth-probe.manual-trigger",
      finalResult: { data: { failureMode: "" } },
    });
    expect(sentryCalls.setTag).toHaveBeenCalledWith(
      "inngest.fn_id",
      "cron-oauth-probe",
    );
    expect(sentryCalls.setTag).toHaveBeenCalledWith("inngest.run_id", "run-42");
    expect(sentryCalls.setTag).toHaveBeenCalledWith(
      "inngest.event_name",
      "cron/oauth-probe.manual-trigger",
    );
    expect(sentryCalls.setExtra).toHaveBeenCalledWith(
      "inngest.event_data",
      expect.any(Object),
    );
  });

  it("attaches event_data as extra (PII routed through sentry scrubber downstream)", async () => {
    await runHooks({
      eventData: { foo: "bar", count: 3 },
      finalResult: { data: {} },
    });
    expect(sentryCalls.setExtra).toHaveBeenCalledWith("inngest.event_data", {
      foo: "bar",
      count: 3,
    });
  });

  it("emits start + execution-{start,end} + final-ok breadcrumbs on success", async () => {
    await runHooks({ finalResult: { data: { ok: true } } });
    const categories = sentryCalls.addBreadcrumb.mock.calls.map(
      ([b]) => (b as { category: string }).category,
    );
    expect(categories).toContain("inngest.run"); // start + final
    expect(categories).toContain("inngest.step"); // execution-start/end
    const messages = sentryCalls.addBreadcrumb.mock.calls.map(
      ([b]) => (b as { message: string }).message,
    );
    expect(messages.some((m) => m.startsWith("start "))).toBe(true);
    expect(messages.some((m) => m.startsWith("final ok "))).toBe(true);
  });

  it("captures final error to Sentry on transformOutput(error, no step)", async () => {
    const err = new Error("probe died");
    await runHooks({ finalResult: { error: err } });
    expect(sentryCalls.captureException).toHaveBeenCalledTimes(1);
    const [capturedErr, capturedOpts] =
      sentryCalls.captureException.mock.calls[0]!;
    expect(capturedErr).toBe(err);
    expect(capturedOpts).toMatchObject({
      tags: {
        "inngest.fn_id": expect.any(String),
        "inngest.run_id": expect.any(String),
        "inngest.event_name": expect.any(String),
      },
    });
  });

  it("does NOT captureException on per-step error (Inngest retries — step is recoverable)", async () => {
    await runHooks({
      steps: [{ name: "probe", result: { error: new Error("transient") } }],
      finalResult: { data: { ok: true } },
    });
    expect(sentryCalls.captureException).not.toHaveBeenCalled();
    // But DOES emit a warning breadcrumb for the step.
    const warningBreadcrumbs = sentryCalls.addBreadcrumb.mock.calls.filter(
      ([b]) => (b as { level: string }).level === "warning",
    );
    expect(warningBreadcrumbs.length).toBeGreaterThanOrEqual(1);
  });

  it("wraps non-Error final result into an Error instance", async () => {
    await runHooks({ finalResult: { error: "string error" } });
    expect(sentryCalls.captureException).toHaveBeenCalledTimes(1);
    const [capturedErr] = sentryCalls.captureException.mock.calls[0]!;
    expect(capturedErr).toBeInstanceOf(Error);
    expect((capturedErr as Error).message).toContain("string error");
  });

  it("silently swallows Sentry SDK exceptions — observability must not kill the run", async () => {
    sentryCalls.captureException.mockImplementation(() => {
      throw new Error("sentry down");
    });
    sentryCalls.addBreadcrumb.mockImplementation(() => {
      throw new Error("sentry down");
    });
    // Should not throw.
    await expect(
      runHooks({ finalResult: { error: new Error("probe died") } }),
    ).resolves.toBeUndefined();
  });
});
