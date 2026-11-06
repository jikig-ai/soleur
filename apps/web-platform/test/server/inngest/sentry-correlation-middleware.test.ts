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
  // Final result delivered to onRunComplete/onRunError.
  finalResult?: { error?: unknown; data?: unknown };
  // isFinalAttempt handed to onRunError for a thrown final result.
  isFinalAttempt?: boolean;
  // Per-step hook invocations BEFORE the final one.
  steps?: Array<{
    name: string;
    op?: string;
    result: { error?: unknown; data?: unknown };
  }>;
}) {
  const { SentryCorrelationMiddleware } = await import(
    "@/server/inngest/middleware/sentry-correlation"
  );
  // v4: the client registers the CLASS; the SDK constructs one instance per
  // request. Tests drive the instance's hooks directly with minimal arg
  // shapes (the `as never` casts keep tsc happy without the full SDK ctx).
  const mw = new SentryCorrelationMiddleware({ client: {} as never });
  const ctx = {
    runId: opts.runId ?? "run-abc-123",
    event: {
      name: opts.eventName ?? "cron/oauth-probe.manual-trigger",
      data: opts.eventData ?? {},
      id: "evt-1",
    },
  };
  const fn = { id: () => opts.fnId ?? "cron-oauth-probe" };
  mw.transformFunctionInput({ ctx, fn, steps: {} } as never);
  mw.onMemoizationEnd?.({ ctx, fn } as never);
  for (const s of opts.steps ?? []) {
    const stepInfo = { options: { id: s.name }, hashedId: s.name, stepType: "run", memoized: false };
    mw.onStepStart?.({ ctx, fn, stepInfo } as never);
    if (s.result.error != null) {
      mw.onStepError?.({ ctx, fn, error: s.result.error, stepInfo, isFinalAttempt: false } as never);
    } else {
      mw.onStepComplete?.({ ctx, fn, stepInfo, output: s.result.data } as never);
    }
  }
  if (opts.finalResult !== undefined) {
    if (opts.finalResult.error != null) {
      await mw.onRunError?.({
        ctx,
        fn,
        error: opts.finalResult.error,
        isFinalAttempt: opts.isFinalAttempt ?? true,
      } as never);
    } else {
      await mw.onRunComplete?.({ ctx, fn, output: opts.finalResult.data } as never);
    }
  }
}

describe("sentry-correlation middleware", () => {
  it("tags scope with fn_id, run_id, event_name on transformFunctionInput", async () => {
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

  it("captures final error to Sentry on onRunError(error, final attempt)", async () => {
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

  it("non-final failed attempt is gated on the native isFinalAttempt flag (regression: dead gate)", async () => {
    // A thrown error on a non-final attempt will retry — capturing it would
    // file a Sentry ISSUE for a recoverable error. The gate lives on
    // onRunError's native isFinalAttempt (sentry-correlation.ts), so a
    // regression that ignores the flag is red here. Pattern mirrors
    // run-log-middleware.test.ts's "non-final failed attempt" row.
    await runHooks({
      finalResult: { error: new Error("retry me") },
      isFinalAttempt: false,
    });
    expect(sentryCalls.captureException).not.toHaveBeenCalled();
    // The non-final attempt still records a warning breadcrumb, not silence.
    const warningBreadcrumbs = sentryCalls.addBreadcrumb.mock.calls.filter(
      ([b]) => (b as { level: string }).level === "warning",
    );
    expect(
      warningBreadcrumbs.some(([b]) =>
        (b as { message: string }).message.startsWith("attempt error "),
      ),
    ).toBe(true);
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
