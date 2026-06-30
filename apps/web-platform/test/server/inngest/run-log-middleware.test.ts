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

import { runLogMiddleware } from "@/server/inngest/middleware/run-log";

interface RunOpts {
  fnId?: string;
  eventName?: string;
  data?: Record<string, unknown>;
  attempt?: number;
  maxAttempts?: number;
}

// Drive the middleware's per-run hooks the way Inngest ACTUALLY does:
// onFunctionRun receives InitialRunInfo ({ event, runId } only — NO attempt/
// maxAttempts); the retry-attempt fields arrive on transformInput's ctx. The
// helper deliberately keeps attempt OFF the onFunctionRun ctx so a regression
// that reads attempt from the wrong ctx (the dead-gate bug) fails this test.
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
  // @ts-expect-error — minimal ctx/fn shapes for the unit test
  const hooks = runLogMiddleware.init().onFunctionRun({ ctx, fn });
  // transformInput's ctx (BaseContext) is where attempt/maxAttempts live.
  const inputCtx = {
    ctx: { attempt: opts.attempt ?? 0, maxAttempts: opts.maxAttempts ?? 1 },
  };
  return { ...hooks, inputCtx };
}

beforeEach(() => {
  rpcMock.mockReset();
  rpcMock.mockResolvedValue({ error: null });
  captureExceptionMock.mockReset();
});

describe("run-log middleware — final-attempt gate", () => {
  it("a fail-then-succeed run writes exactly one 'completed' row", async () => {
    // attempt 0 fails (non-final, maxAttempts=2) → no write
    const a0 = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a0.transformInput?.(a0.inputCtx as never);
    await a0.transformOutput?.({ result: { error: new Error("boom") } } as never);
    expect(rpcMock).not.toHaveBeenCalled();

    // attempt 1 succeeds → exactly one write, status completed
    const a1 = makeHooks({ attempt: 1, maxAttempts: 2 });
    await a1.transformInput?.(a1.inputCtx as never);
    await a1.transformOutput?.({ result: { data: "ok" } } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][0]).toBe("write_routine_run");
    expect(rpcMock.mock.calls[0][1].p_status).toBe("completed");
  });

  it("a final failed attempt writes one 'failed' row", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { error: new Error("nope") } } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
  });

  it("a non-final failed attempt is gated even when maxAttempts is read from transformInput (regression: dead gate)", async () => {
    // attempt 1 of 3 fails → must NOT write. This only passes if attempt/
    // maxAttempts are sourced from transformInput's ctx; the prior bug read
    // them off onFunctionRun's ctx (always undefined → always "final").
    const a = makeHooks({ attempt: 1, maxAttempts: 3 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { error: new Error("retry me") } } as never);
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it("a step-level output (step present) writes no row — only the function-final result lands", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { data: "step-out" }, step: {} } as never);
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — returned ok:false is terminal (#5674 P0 guard)", () => {
  it("a returned { ok:false } on attempt 0 of maxAttempts:2 (NON-final) WRITES a failed row with a non-null scrubbed summary", async () => {
    // The exact case the first plan draft got wrong: a returned ok:false is
    // TERMINAL under retries:1 (no retry), so the final-attempt gate must NOT
    // suppress it — it must be written on the spot.
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({
      result: {
        error: null,
        data: { ok: false, errorSummary: "Credit balance is too low" },
      },
    } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBe(
      "Credit balance is too low",
    );
  });

  it("a returned { ok:false } with NO errorSummary still records a non-null fallback reason", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({
      result: { error: null, data: { ok: false } },
    } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBe(
      "cron returned ok:false (see Sentry)",
    );
  });

  it("a returned { ok:true } writes completed / error_summary null", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({
      result: { error: null, data: { ok: true } },
    } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("completed");
    expect(rpcMock.mock.calls[0][1].p_error_summary).toBeNull();
  });

  it("a THROWN error on a non-final attempt is still gated (will retry → no write)", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 2 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { error: new Error("boom") } } as never);
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — error_summary scrubbing", () => {
  it("redacts secrets/PII and truncates the first line of a failed run's error", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({
      result: {
        error: new Error(
          "auth failed for postgres://user:s3cr3tpw@db.host:5432/x — token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 contact ops@example.com\nsecond line should be dropped",
        ),
      },
    } as never);
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
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { data: "ok" } } as never);
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
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { data: "ok" } } as never);
    const args = rpcMock.mock.calls[0][1];
    expect(args.p_trigger_source).toBe("agent");
    expect(args.p_actor_class).toBe("agent");
    expect(args.p_actor_id).toBe("u1");
    expect(args.p_delegating_principal).toBe("op1");
  });

  it("does not write for non-routine (event-driven) functions", async () => {
    const a = makeHooks({ fnId: "cfo-on-payment-failed", eventName: "finance.payment_failed" });
    await a.transformInput?.(a.inputCtx as never);
    await a.transformOutput?.({ result: { data: "ok" } } as never);
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — fail-soft", () => {
  it("a throwing RPC does not propagate and mirrors to Sentry", async () => {
    rpcMock.mockRejectedValue(new Error("supabase down"));
    const a = makeHooks({});
    await a.transformInput?.(a.inputCtx as never);
    await expect(
      a.transformOutput?.({ result: { data: "ok" } } as never),
    ).resolves.not.toThrow();
    expect(captureExceptionMock).toHaveBeenCalled();
  });
});
