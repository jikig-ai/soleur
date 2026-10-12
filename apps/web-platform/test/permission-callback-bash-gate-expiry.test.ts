/**
 * #10054 — the generic Bash review gate was dead code until the SDK began calling `canUseTool` for sandboxed Bash.
 * `abortableReviewGate` rejects on timeout or abort; that must be a fail-closed deny with the conversation status
 * restored, never a throw out of `canUseTool` that strands the conversation in `waiting_for_user`.
 */
import { vi, describe, test, expect } from "vitest";

vi.mock("../server/logger", () => {
  const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { createChildLogger: () => log, default: log };
});
vi.mock("../server/permission-log", () => ({ logPermissionDecision: vi.fn() }));

import { createCanUseTool, type CanUseToolContext } from "../server/permission-callback";

function makeCtx(gate: () => Promise<string>, extra: Record<string, unknown> = {}) {
  const deps = {
    abortableReviewGate: vi.fn(gate),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
    ...extra,
  };
  const ctx = {
    userId: "u",
    conversationId: "c",
    leaderId: "cc_router",
    workspacePath: "/tmp/ws",
    platformToolNames: [],
    pluginMcpServerNames: [],
    repoOwner: "",
    repoName: "",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps,
  } as unknown as CanUseToolContext;
  return { ctx, deps };
}

const callBash = (ctx: CanUseToolContext) =>
  createCanUseTool(ctx)(
    "Bash",
    { command: "make deploy-something" },
    { signal: new AbortController().signal, toolUseID: "t", requestId: "r" },
  );

describe("generic Bash gate expiry (#10054)", () => {
  test("a timed-out gate denies and restores the conversation status", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("review gate timeout")));
    const res = await callBash(ctx);
    expect(res?.behavior).toBe("deny");
    const statuses = deps.updateConversationStatus.mock.calls.map((c) => c[1]);
    expect(statuses).toEqual(["waiting_for_user", "active"]);
  });

  test("an approved gate still allows and restores the status", async () => {
    const { ctx, deps } = makeCtx(() => Promise.resolve("Approve"));
    const res = await callBash(ctx);
    expect(res?.behavior).toBe("allow");
    expect(deps.updateConversationStatus.mock.calls.map((c) => c[1])).toEqual(["waiting_for_user", "active"]);
  });
});

// The lifecycle helper behind all three user-facing Bash gates (review card, first-run disclosure, opt-out).
const statuses = (deps: { updateConversationStatus: { mock: { calls: unknown[][] } } }) =>
  deps.updateConversationStatus.mock.calls.map((c) => c[1]);

describe("first-run autonomous-disclosure gate (owner, default-ON workspace, no ack yet)", () => {
  const firstRun = { bashAutonomous: true, autonomousAckAt: null, isOwner: true };

  test("expiry denies (never allows, never throws) and restores the status", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")), firstRun);
    const res = await callBash(ctx);
    expect(res?.behavior).toBe("deny");
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("an unexpected selection denies (only 'Got it' / 'Keep autonomous on' may release the hold)", async () => {
    const { ctx } = makeCtx(() => Promise.resolve("Approve"), {
      ...firstRun,
      verifyAutonomousAck: undefined, // an unwired re-check must not turn an unexpected selection into an allow
    });
    expect((await callBash(ctx))?.behavior).toBe("deny");
  });

  test("'Got it' with the ack persisted still allows", async () => {
    const { ctx } = makeCtx(() => Promise.resolve("Got it"), {
      ...firstRun,
      verifyAutonomousAck: vi.fn().mockResolvedValue("2026-10-11T00:00:00Z"),
    });
    expect((await callBash(ctx))?.behavior).toBe("allow");
  });
});

describe("existing-workspace opt-out gate (owner, autonomous off, no ack yet)", () => {
  const optOut = { bashAutonomous: false, autonomousAckAt: null, isOwner: true };

  test("expiry denies instead of falling through to a second card, and restores the status", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")), optOut);
    const res = await callBash(ctx);
    expect(res?.behavior).toBe("deny");
    expect(deps.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });
});

describe("gate lifecycle guarantees", () => {
  test("a failing status write never replaces the verdict", async () => {
    const { ctx, deps } = makeCtx(() => Promise.reject(new Error("timeout")));
    deps.updateConversationStatus.mockRejectedValue(new Error("db down"));
    const res = await callBash(ctx);
    expect(res?.behavior).toBe("deny"); // a throw out of the finally would have replaced this
  });

  test("stacked cards: the status goes active only when the LAST pending gate resolves", async () => {
    const resolvers: Array<(v: string) => void> = [];
    const { ctx, deps } = makeCtx(() => new Promise<string>((r) => resolvers.push(r)));
    const run = createCanUseTool(ctx);
    const call = (cmd: string) =>
      run("Bash", { command: cmd }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" });
    const results = Promise.all([call("make one"), call("make two")]);
    await new Promise((r) => setTimeout(r, 10));
    expect(resolvers).toHaveLength(2);
    resolvers[0]("Approve");
    await new Promise((r) => setTimeout(r, 10));
    expect(statuses(deps)).toEqual(["waiting_for_user"]); // the other card is still pending: NOT active yet
    resolvers[1]("Reject");
    const done = await results;
    expect(done.map((d) => d?.behavior).sort()).toEqual(["allow", "deny"]);
    expect(statuses(deps)).toEqual(["waiting_for_user", "active"]);
  });

  test("the expiry deny tells the agent the command did NOT run and not to retry or respell it", async () => {
    const { ctx } = makeCtx(() => Promise.reject(new Error("timeout")));
    const res = (await callBash(ctx)) as { message: string };
    expect(res.message).toMatch(/not run/i);
    expect(res.message).toMatch(/do not retry/i);
    expect(res.message).toMatch(/rephrase|respell/i);
  });
});
