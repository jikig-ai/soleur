/**
 * #4672: the gated branch of `createCanUseTool` hands a slice-1 tool to the approval gate and returns the gate's verdict.
 *
 * A narrow, DB-free detector for the two edits that sit on the chokepoint every gate test passes through (battery rows
 * G1-PC1: the branch never calls the gate; G1-PC2: the gate's verdict is discarded and the call falls through to the legacy
 * review card). Those edits turned most of gate-flow.test.ts red, which is a crash-shaped signal, not an attribution; here
 * exactly the tests named below go red. The gate's own behaviour is proven in gate-flow.test.ts.
 *
 * Synthesized data only.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";

const { log } = vi.hoisted(() => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { createCanUseTool, type CanUseToolContext } from "@/server/permission-callback";
import { APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters } from "@/server/approval/waiters";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

beforeEach(() => {
  clearAllWaiters();
  process.env.SENTRY_USERID_PEPPER = "permission-callback-gated-branch-test-pepper";
});

function setup(enabled: boolean) {
  const isEnabled = vi.fn(async () => enabled);
  // The bind step fails: with the flag on the gate answers the static unavailable deny, without ever touching a database.
  const resolveServerDerived = vi.fn(async () => {
    throw new Error("bind failed");
  });
  const approval = {
    isEnabled,
    workspaceId: WORKSPACE_ID,
    grants: new ExecutionGrants(),
    resolveServerDerived,
    submit: vi.fn(),
    readStatus: vi.fn(),
    consume: vi.fn(),
    viewerRole: vi.fn(async () => "owner" as const),
  } as unknown as ApprovalGateDeps;
  const abortableReviewGate = vi.fn(() => Promise.resolve("Approve"));
  const ctx = {
    userId: USER_ID,
    conversationId: CONVERSATION_ID,
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: [...APPROVAL_REQUIRED_TOOLS, "mcp__soleur_platform__create_issue"],
    pluginMcpServerNames: [],
    repoOwner: "example-org",
    repoName: "example-repo",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps: {
      abortableReviewGate,
      sendToClient: vi.fn(() => true),
      notifyOfflineUser: vi.fn().mockResolvedValue(true),
      updateConversationStatus: vi.fn(async () => {}),
      approval,
    },
  } as unknown as CanUseToolContext;
  const call = (tool: string, input: Record<string, unknown>) =>
    createCanUseTool(ctx)(tool, input, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never) as Promise<{
      behavior: string;
      message?: string;
    }>;
  return { call, isEnabled, resolveServerDerived, abortableReviewGate };
}

describe("the gated branch of createCanUseTool", () => {
  test("an approval-required tool with the flag on is handed to the approval gate and returns the gate's verdict (the legacy review card is never reached)", async () => {
    const h = setup(true);
    const res = await h.call(TOOLS.emailSend, SAMPLES[TOOLS.emailSend].input);
    expect(h.isEnabled).toHaveBeenCalledTimes(1);
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("with the flag off the gate returns null and the call falls through to the legacy review card, unchanged", async () => {
    const h = setup(false);
    const res = await h.call(TOOLS.emailSend, SAMPLES[TOOLS.emailSend].input);
    expect(h.resolveServerDerived).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(res.behavior).toBe("allow");
  });

  test("a gated tool outside the approval set never reaches the approval gate", async () => {
    const h = setup(true);
    await h.call("mcp__soleur_platform__create_issue", { title: "t", body: "b" });
    expect(h.isEnabled).not.toHaveBeenCalled();
  });
});
