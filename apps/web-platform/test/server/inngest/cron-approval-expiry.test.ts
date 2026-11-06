// #4672 — cron-approval-expiry handler: sweep, notify, marker and heartbeat ordering and failure isolation.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
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

import { cronApprovalExpiry, cronApprovalExpiryHandler, SENTRY_MONITOR_SLUG } from "@/server/inngest/functions/cron-approval-expiry";

const stepRun = vi.fn(async (_n: string, fn: () => unknown) => fn());
const step = { run: stepRun };
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
const args = { step, logger } as unknown as Parameters<typeof cronApprovalExpiryHandler>[0];

const EXP = (id: string, reason: "unanswered" | "unconsumed") => ({ id, workspaceId: "w1", toolName: "mcp__soleur_platform__email_send", reason });

describe("cronApprovalExpiryHandler", () => {
  beforeEach(() => {
    for (const f of Object.values(h)) f.mockReset();
    stepRun.mockClear();
    h.notify.mockResolvedValue(true);
  });

  it("an empty sweep still emits the lifecycle marker and an ok heartbeat, with no push and no Sentry op", async () => {
    h.sweep.mockResolvedValue({ expired: [], flagged: [], scrubbed: 0 });
    const r = await cronApprovalExpiryHandler(args);
    expect(r).toEqual({ ok: true, expired: 0, flagged: 0, scrubbed: 0, notifyFailed: 0 });
    expect(h.notify).not.toHaveBeenCalled();
    expect(h.op).not.toHaveBeenCalled();
    // The notify step is skipped entirely when both result arrays are empty (no billed empty step every 5 minutes).
    expect(stepRun.mock.calls.map((c) => c[0])).toEqual(["approval-sweep", "approval-sweep-marker", "sentry-heartbeat"]);
    expect(h.marker).toHaveBeenCalledWith("SOLEUR_APPROVAL_SWEEP", expect.objectContaining({ ok: true }));
    expect(h.heartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }));
  });

  it("pushes only for an unanswered expiry; an unconsumed expiry is inbox-only", async () => {
    h.sweep.mockResolvedValue({ expired: [EXP("a1", "unanswered"), EXP("a2", "unconsumed")], flagged: [], scrubbed: 3 });
    const r = await cronApprovalExpiryHandler(args);
    expect(h.notify).toHaveBeenCalledTimes(1);
    expect(h.notify).toHaveBeenCalledWith("a1", "w1");
    expect(stepRun.mock.calls.map((c) => c[0])).toContain("approval-notify");
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
    const boom = Object.assign(new Error("boom"), { code: "ECONNRESET" });
    h.notify.mockRejectedValue(boom);
    await expect(cronApprovalExpiryHandler(args)).resolves.toMatchObject({ ok: true, notifyFailed: 1 });
    // The cause is KEPT (the op reads its code / class name; never the message), and a plain not-delivered says so.
    expect(h.op).toHaveBeenCalledWith("notifyFailed", boom, expect.objectContaining({ approvalId: "a1", extra: { kind: "expired", cause: "threw" } }));
  });

  it("a push that answers false is reported without an error and says why", async () => {
    h.sweep.mockResolvedValue({ expired: [EXP("a1", "unanswered")], flagged: [], scrubbed: 0 });
    h.notify.mockResolvedValue(false);
    await cronApprovalExpiryHandler(args);
    expect(h.op).toHaveBeenCalledWith("notifyFailed", null, expect.objectContaining({ extra: { kind: "expired", cause: "not-delivered" } }));
  });

  it("flagged rows are reported as unanswered ops and not pushed", async () => {
    h.sweep.mockResolvedValue({ expired: [], flagged: [{ id: "f1", workspaceId: "w1", toolName: "t" }], scrubbed: 0 });
    await cronApprovalExpiryHandler(args);
    expect(h.op).toHaveBeenCalledWith("gateUnanswered", null, expect.objectContaining({ approvalId: "f1" }));
    expect(h.notify).not.toHaveBeenCalled();
    expect(stepRun.mock.calls.map((c) => c[0])).toContain("approval-notify");
  });

  it("an RPC failure is one sweepFailed op, no push, and a red heartbeat", async () => {
    h.sweep.mockRejectedValue(new Error("rpc down"));
    const r = await cronApprovalExpiryHandler(args);
    expect(r).toMatchObject({ ok: false, expired: 0 });
    // `extra.cron`, never `extra.fn`: `fn` is the failing RPC name the error contributes, and extra overwrites it.
    expect(h.op).toHaveBeenCalledWith("sweepFailed", expect.any(Error), { extra: { cron: "cron-approval-expiry" } });
    expect(h.notify).not.toHaveBeenCalled();
    expect(stepRun.mock.calls.map((c) => c[0])).not.toContain("approval-notify");
    expect(h.heartbeat).toHaveBeenCalledWith(expect.objectContaining({ ok: false }));
  });
});

// The registration (not the handler) owns the lane. The shared "cron-platform" account lane is held 50-70 min by
// claude-eval, which would delay the sweep and false-page its monitor; the dedicated key mirrors cron-bot-pr-reaper.
describe("cronApprovalExpiry registration", () => {
  const src = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../../server/inngest/functions/cron-approval-expiry.ts"), "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .filter((l) => !/^\s*\/\//.test(l))
    .join("\n");

  it("runs on its own account concurrency lane and not the shared cron-platform one", () => {
    expect(src).toContain(`{ scope: "fn", limit: 1 }`);
    expect(src).toContain(`{ scope: "account", key: '"cron-approval-expiry"', limit: 1 }`);
    expect(src).not.toContain(`"cron-platform"`);
    expect(cronApprovalExpiry).toBeDefined();
  });
});
