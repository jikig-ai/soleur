// #4672 — cron-approval-expiry handler: sweep, notify, marker and heartbeat ordering and failure isolation.
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const h = vi.hoisted(() => ({
  sweep: vi.fn(),
  notify: vi.fn(),
  op: vi.fn(),
  marker: vi.fn(),
  heartbeat: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({}) }));
vi.mock("@/server/approval/service", () => ({ sweepApprovals: (...a: unknown[]) => h.sweep(...a) }));
vi.mock("@/server/approval/notify", () => ({ notifyApprovalExpired: (...a: unknown[]) => h.notify(...a) }));
vi.mock("@/server/approval/ops", () => ({
  reportApprovalOp: (...a: unknown[]) => h.op(...a),
  logApprovalMarker: (...a: unknown[]) => h.marker(...a),
}));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return { ...actual, postSentryHeartbeat: (...a: unknown[]) => h.heartbeat(...a) };
});

import { cronApprovalExpiryHandler, SENTRY_MONITOR_SLUG } from "@/server/inngest/functions/cron-approval-expiry";

const step = { run: async (_n: string, fn: () => unknown) => fn() };
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
const args = { step, logger } as unknown as Parameters<typeof cronApprovalExpiryHandler>[0];

const EXP = (id: string, reason: "unanswered" | "unconsumed") => ({ id, workspaceId: "w1", toolName: "mcp__soleur_platform__email_send", reason });

describe("cronApprovalExpiryHandler", () => {
  beforeEach(() => {
    for (const f of Object.values(h)) f.mockReset();
    h.notify.mockResolvedValue(true);
  });

  it("an empty sweep still emits the lifecycle marker and an ok heartbeat, with no push and no Sentry op", async () => {
    h.sweep.mockResolvedValue({ expired: [], flagged: [], scrubbed: 0 });
    const r = await cronApprovalExpiryHandler(args);
    expect(r).toEqual({ ok: true, expired: 0, flagged: 0, scrubbed: 0, notifyFailed: 0 });
    expect(h.notify).not.toHaveBeenCalled();
    expect(h.op).not.toHaveBeenCalled();
    expect(h.marker).toHaveBeenCalledWith("SOLEUR_APPROVAL_SWEEP", expect.objectContaining({ ok: true }));
    expect(h.heartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }));
  });

  it("pushes only for an unanswered expiry; an unconsumed expiry is inbox-only", async () => {
    h.sweep.mockResolvedValue({ expired: [EXP("a1", "unanswered"), EXP("a2", "unconsumed")], flagged: [], scrubbed: 3 });
    const r = await cronApprovalExpiryHandler(args);
    expect(h.notify).toHaveBeenCalledTimes(1);
    expect(h.notify).toHaveBeenCalledWith("a1");
    expect(r).toMatchObject({ ok: true, expired: 2, scrubbed: 3, notifyFailed: 0 });
  });

  it("a failed push is counted and reported, and never fails the sweep or the heartbeat", async () => {
    h.sweep.mockResolvedValue({ expired: [EXP("a1", "unanswered")], flagged: [], scrubbed: 0 });
    h.notify.mockResolvedValue(false);
    const r = await cronApprovalExpiryHandler(args);
    expect(r).toMatchObject({ ok: true, notifyFailed: 1 });
    expect(h.op).toHaveBeenCalledWith("notifyFailed", null, expect.objectContaining({ approvalId: "a1" }));
    expect(h.heartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true }));
  });

  it("a throwing push is treated as a failed push", async () => {
    h.sweep.mockResolvedValue({ expired: [EXP("a1", "unanswered")], flagged: [], scrubbed: 0 });
    h.notify.mockRejectedValue(new Error("boom"));
    await expect(cronApprovalExpiryHandler(args)).resolves.toMatchObject({ ok: true, notifyFailed: 1 });
  });

  it("flagged rows are reported as unanswered ops and not pushed", async () => {
    h.sweep.mockResolvedValue({ expired: [], flagged: [{ id: "f1", workspaceId: "w1", toolName: "t" }], scrubbed: 0 });
    await cronApprovalExpiryHandler(args);
    expect(h.op).toHaveBeenCalledWith("gateUnanswered", null, expect.objectContaining({ approvalId: "f1" }));
    expect(h.notify).not.toHaveBeenCalled();
  });

  it("an RPC failure is one sweepFailed op, no push, and a red heartbeat", async () => {
    h.sweep.mockRejectedValue(new Error("rpc down"));
    const r = await cronApprovalExpiryHandler(args);
    expect(r).toMatchObject({ ok: false, expired: 0 });
    expect(h.op).toHaveBeenCalledWith("sweepFailed", expect.any(Error), expect.anything());
    expect(h.notify).not.toHaveBeenCalled();
    expect(h.heartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });
});
