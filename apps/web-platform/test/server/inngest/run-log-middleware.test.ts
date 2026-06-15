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

// Drive the middleware's per-run hooks the way Inngest would.
function makeHooks(opts: RunOpts) {
  const fnId = opts.fnId ?? "cron-daily-triage";
  const ctx = {
    runId: "run-abc",
    attempt: opts.attempt ?? 0,
    maxAttempts: opts.maxAttempts ?? 1,
    event: {
      name: opts.eventName ?? "cron/daily-triage.manual-trigger",
      data: opts.data ?? {},
    },
  };
  const fn = { id: () => fnId };
  // @ts-expect-error — minimal ctx/fn shapes for the unit test
  return runLogMiddleware.init().onFunctionRun({ ctx, fn });
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
    await a0.transformInput?.();
    await a0.transformOutput?.({ result: { error: new Error("boom") } } as never);
    expect(rpcMock).not.toHaveBeenCalled();

    // attempt 1 succeeds → exactly one write, status completed
    const a1 = makeHooks({ attempt: 1, maxAttempts: 2 });
    await a1.transformInput?.();
    await a1.transformOutput?.({ result: { data: "ok" } } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][0]).toBe("write_routine_run");
    expect(rpcMock.mock.calls[0][1].p_status).toBe("completed");
  });

  it("a final failed attempt writes one 'failed' row", async () => {
    const a = makeHooks({ attempt: 0, maxAttempts: 1 });
    await a.transformInput?.();
    await a.transformOutput?.({ result: { error: new Error("nope") } } as never);
    expect(rpcMock).toHaveBeenCalledTimes(1);
    expect(rpcMock.mock.calls[0][1].p_status).toBe("failed");
  });
});

describe("run-log middleware — attribution", () => {
  it("derives trigger_source=scheduled/actor_class=system from a non-manual event name (ignores forged data)", async () => {
    const a = makeHooks({
      eventName: "inngest/scheduled.timer",
      data: { actor_class: "human", actor_id: "forged" },
    });
    await a.transformInput?.();
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
    await a.transformInput?.();
    await a.transformOutput?.({ result: { data: "ok" } } as never);
    const args = rpcMock.mock.calls[0][1];
    expect(args.p_trigger_source).toBe("agent");
    expect(args.p_actor_class).toBe("agent");
    expect(args.p_actor_id).toBe("u1");
    expect(args.p_delegating_principal).toBe("op1");
  });

  it("does not write for non-routine (event-driven) functions", async () => {
    const a = makeHooks({ fnId: "cfo-on-payment-failed", eventName: "finance.payment_failed" });
    await a.transformInput?.();
    await a.transformOutput?.({ result: { data: "ok" } } as never);
    expect(rpcMock).not.toHaveBeenCalled();
  });
});

describe("run-log middleware — fail-soft", () => {
  it("a throwing RPC does not propagate and mirrors to Sentry", async () => {
    rpcMock.mockRejectedValue(new Error("supabase down"));
    const a = makeHooks({});
    await a.transformInput?.();
    await expect(
      a.transformOutput?.({ result: { data: "ok" } } as never),
    ).resolves.not.toThrow();
    expect(captureExceptionMock).toHaveBeenCalled();
  });
});
