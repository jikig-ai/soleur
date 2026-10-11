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

function makeCtx(gate: () => Promise<string>) {
  const deps = {
    abortableReviewGate: vi.fn(gate),
    sendToClient: vi.fn().mockReturnValue(true),
    notifyOfflineUser: vi.fn().mockResolvedValue(true),
    updateConversationStatus: vi.fn().mockResolvedValue(undefined),
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
