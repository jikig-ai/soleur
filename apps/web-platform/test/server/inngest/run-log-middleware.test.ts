import { beforeEach, describe, expect, it, vi } from "vitest";

// Capture rpc calls.
const rpcMock = vi.fn();
const captureExceptionMock = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: () => ({ rpc: rpcMock }),
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: (...a: unknown[]) => captureExceptionMock(...a),
  addBreadcrumb: vi.fn(),
  getCurrentScope: () => ({ setTag: vi.fn(), setExtra: vi.fn() }),
}));
// #5766 — spy on the live-state delete so we can assert it fires AFTER a
// successful terminal write and NOT when the write throws (DI-P1-C).
const finishProgressMock = vi.fn();
vi.mock("@/server/inngest/routine-run-progress", () => ({
  finishRoutineRunProgress: (...a: unknown[]) => finishProgressMock(...a),
}));

import { RunLogMiddleware } from "@/server/inngest/middleware/run-log";

interface RunOpts {
  fnId?: string;
  eventName?: string;
  data?: Record<string, unknown>;
  attempt?: number;
  maxAttempts?: number;
}

// Drive the middleware's per-request hooks the way inngest@4 ACTUALLY does:
// a fresh class instance per request; transformFunctionInput receives the full
// run ctx ({ event, runId }), and the terminal result splits across
// onRunComplete (handler returned — success OR returned { ok:false }) and
// onRunError (handler threw — carries the native isFinalAttempt flag that
// retires the v3 `attempt >= maxAttempts - 1` approximation). The attempt/
// maxAttempts opts are translated into that flag, so a regression that
// ignores isFinalAttempt fails this suite.
function makeHooks(opts: RunOpts) {
  const fnId = opts.fnId ?? "cron-daily-triage";
  const ctx = {
    runId: "run-abc",
    event: {
      name: opts.eventName ?? "cron/daily-triage.manual-trigger",
      data: opts.data ?? {},
    },
  };
  const fn = { id: () => fnId };
  const mw = new RunLogMiddleware({ client: {} as never });
  mw.transformFunctionInput({ ctx, fn, steps: {} } as never);
  const isFinal = (opts.attempt ?? 0) >= (opts.maxAttempts ?? 1) - 1;
  return {
    mw,
    // v3 transformOutput({ result: { data } }) → v4 onRunComplete({ output })
    runComplete: (output: unknown) =>
      mw.onRunComplete({ ctx, fn, output } as never),
    // v3 transformOutput({ result: { error } }) → v4 onRunError({ error, isFinalAttempt })
    runError: (error: unknown, final = isFinal) =>
      mw.onRunError({ ctx, fn, error, isFinalAttempt: final } as never),
  };
}

beforeEach(() => {
  rpcMock.mockReset();
  rpcMock.mockResolvedValue({ error: null });
  captureExceptionMock.mockReset();
  finishProgressMock.mockReset();
});

describe("run-log middleware — live-state finish ordering (#5766 AC6 / DI-P1-C)", () => {
  it("deletes the live row AFTER a successful terminal write", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.runComplete("ok");
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(finishProgressMock).toHaveBeenCalledWith("run-abc");
    // Ordering: the terminal write is invoked BEFORE the live-row delete.
    expect(rpcMock.mock.invocationCallOrder[0]).toBeLessThan(
      finishProgressMock.mock.invocationCallOrder[0],
    );
  });

  it("does NOT delete the live row when the terminal write throws (run stays visible as stuck, never vanishes)", async () => {
    rpcMock.mockRejectedValueOnce(new Error("db down"));
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.runComplete("ok");
    expect(finishProgressMock).not.toHaveBeenCalled();
  });

  it("does NOT delete on a step-level event (no terminal row yet)", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    // v4: step-level results are onStepComplete/onStepError — this middleware
    // defines neither, so a step event can never reach the row writer.
    expect((a.mw as { onStepComplete?: unknown }).onStepComplete).toBeUndefined();
    expect((a.mw as { onStepError?: unknown }).onStepError).toBeUndefined();
    expect(rpcMock).not.toHaveBeenCalled();
    expect(finishProgressMock).not.toHaveBeenCalled();
  });

  it("does NOT delete on a non-final failed attempt (write is gated, so is the delete)", async () => {
    const a = makeHooks({ attempt: 1, maxAttempts: 3 });
    await a.runError(new Error("retry"));
    expect(rpcMock).not.toHaveBeenCalled();
    expect(finishProgressMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — final-attempt gate", () => {
  it("a fail-then-succeed run writes exactly one 'completed' row", async () => {
    // attempt 0 fails (non-final, maxAttempts=2) → no write
    const a0 = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a0.runError(new Error("boom"));
    expect(rpcMock).not.toHaveBeenCalled();

    // attempt 1 succeeds → exactly one write, status completed
    const a1 = makeHooks({ attempt: 1, maxAttempts: 2 });
    await a1.runComplete("ok");
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][0]).toBe("write_routine_run");
    expect(rpcMock.mock.calls[0][1].p_status).toBe("completed");
  });

  it("a final failed attempt writes one 'failed' row", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.runError(new Error("nope"));
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
  });

  it("a non-final failed attempt is gated on the native isFinalAttempt flag (regression: dead gate)", async () => {
    // attempt 1 of 3 fails → must NOT write. Under v4 the flag arrives on
    // onRunError directly — the v3 transformInput ctx capture is gone, so a
    // regression that ignores isFinalAttempt is the only shape left to pin.
    const a = makeHooks({ attempt: 1, maxAttempts: 3 });
    await a.runError(new Error("retry me"));
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it("a step-level output (step present) writes no row — only the function-final result lands", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    // Same pin as above: no step-level hook exists, so only a run-final
    // hook can land a row.
    expect((a.mw as { onStepComplete?: unknown }).onStepComplete).toBeUndefined();
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — returned ok:false is terminal (#5674 P0 guard)", () => {
  it("a returned { ok:false } on attempt 0 of maxAttempts:2 (NON-final) WRITES a failed row with a non-null scrubbed summary", async () => {
    // The exact case the first plan draft got wrong: a returned ok:false is
    // TERMINAL under retries:1 (no retry), so the final-attempt gate must NOT
    // suppress it — it must be written on the spot.
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.runComplete({ ok: false, errorSummary: "Credit balance is too low" });
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBe(
      "Credit balance is too low",
    );
  });

  it("a returned { ok:false } with NO errorSummary still records a non-null fallback reason", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.runComplete({ ok: false });
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBe(
      "cron returned ok:false (see Sentry)",
    );
  });

  it("a returned { ok:true } writes completed / error_summary null", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.runComplete({ ok: true });
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("completed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBeNull();
  });

  it("a THROWN error on a non-final attempt is still gated (will retry → no write)", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.runError(new Error("boom"));
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — error_summary scrubbing", () => {
  it("redacts secrets/PII and truncates the first line of a failed run's error", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.runError(
      new Error(
        "auth failed for postgres://user:s3cr3tpw@db.host:5432/x — token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 contact ops@example.com\nsecond line should be dropped",
      ),
    );
    expect(rpcMock).toHaveBeenCalledTimes(1);
    const summary: string = rpcMock.mock.calls[0][1].p_error_summary;
    // First-line only.
    expect(summary).not.toContain("second line");
    // Secrets/PII scrubbed.
    expect(summary).not.toContain("s3cr3tpw");
    expect(summary).not.toContain("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789");
    expect(summary).not.toContain("ops@example.com");
    expect(summary.length).toBeLessThanOrEqual(500);
  });
});

describe("run-log middleware — attribution", () => {
  it("derives trigger_source=scheduled/actor_class=system from a non-manual event name (ignores forged data)", async () => {
    const a = makeHooks({
      eventName: "inngest/scheduled.timer",
      data: { actor_class: "human", actor_id: "forged" },
    });
    await a.runComplete("ok");
    const args = rpcMock.mock.calls[0][1];
    expect(args.p_trigger_source).toBe("scheduled");
    expect(args.p_actor_class).toBe("system");
    expect(args.p_actor_id).toBeNull();
  });

  it("records manual/agent attribution from a manual-trigger event", async () => {
    const a = makeHooks({
      eventName: "cron/daily-triage.manual-trigger",
      data: { trigger: "agent", actor_class: "agent", actor_id: "u1", delegating_principal: "op1" },
    });
    await a.runComplete("ok");
    const args = rpcMock.mock.calls[0][1];
    expect(args.p_trigger_source).toBe("agent");
    expect(args.p_actor_class).toBe("agent");
    expect(args.p_actor_id).toBe("u1");
    expect(args.p_delegating_principal).toBe("op1");
  });

  it("does not write for non-routine (event-driven) functions", async () => {
    const a = makeHooks({ fnId: "cfo-on-payment-failed", eventName: "finance.payment_failed" });
    await a.runComplete("ok");
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — fail-soft", () => {
  it("a throwing RPC does not propagate and mirrors to Sentry", async () => {
    rpcMock.mockRejectedValue(new Error("supabase down"));
    const a = makeHooks({});
    await expect(a.runComplete("ok")).resolves.not.toThrow();
    expect(captureExceptionMock).toHaveBeenCalled();
  });
});
