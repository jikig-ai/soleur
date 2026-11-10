/**
 * #12197 (CTO ruling D1, 2026-11-10): when the approval flow gives no verdict (flag off or unreadable, or no dependency), the
 * legacy runner's in-memory push card may be answered only by the workspace Owner. A member, a failed role read or a missing
 * dependency is the static deny, with no card. Settings' PUSH_DISCLOSURE ("nothing is pushed that way unless the workspace
 * owner approves that push") relies on this. Other approval-required tools keep the in-memory card (narrow scope pin).
 *
 * Synthesized data only.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";

const { log, reports } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  reports: [] as unknown[][],
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...args: unknown[]) => {
    reports.push(args);
  },
}));

import { createCanUseTool, PUSH_ROLE_READ_DEADLINE_MS, type CanUseToolContext } from "@/server/permission-callback";
import { APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters } from "@/server/approval/waiters";
import { APPROVAL_REQUIRED_TOOLS, GITHUB_PUSH_BRANCH_TOOL } from "@/server/approval/tools";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

beforeEach(() => {
  clearAllWaiters();
  reports.length = 0;
  log.warn.mockClear();
  process.env.SENTRY_USERID_PEPPER = "legacy-push-owner-fallback-test-pepper";
});

type Role = "owner" | "member" | "throws" | "no-approval" | "member-flag-throws";

function setup(role: Role, opts: { viewerRole?: () => Promise<"owner" | "member">; callSignal?: AbortSignal } = {}) {
  const viewerRole = vi.fn(
    opts.viewerRole ??
      (async () => {
        if (role === "throws") throw new Error("viewer role read failed");
        return role === "owner" ? ("owner" as const) : ("member" as const);
      }),
  );
  // The flag is off, so the approval flow answers null (no verdict) and the call reaches the in-memory fallback.
  const approval = {
    isEnabled: vi.fn(async () => {
      if (role === "member-flag-throws") throw new Error("flagsmith down");
      return false;
    }),
    workspaceId: WORKSPACE_ID,
    grants: new ExecutionGrants(),
    resolveServerDerived: vi.fn(),
    submit: vi.fn(),
    readStatus: vi.fn(),
    consume: vi.fn(),
    viewerRole,
  } as unknown as ApprovalGateDeps;
  const abortableReviewGate = vi.fn(() => Promise.resolve("Approve"));
  const sendToClient = vi.fn(() => true);
  const notifyOfflineUser = vi.fn().mockResolvedValue(true);
  const updateConversationStatus = vi.fn(async () => {});
  const ctx = {
    userId: USER_ID,
    conversationId: CONVERSATION_ID,
    leaderId: "cto",
    workspacePath: "/tmp/ws",
    platformToolNames: [...APPROVAL_REQUIRED_TOOLS],
    pluginMcpServerNames: [],
    repoOwner: "example-org",
    repoName: "example-repo",
    session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
    controllerSignal: new AbortController().signal,
    deps: {
      abortableReviewGate,
      sendToClient,
      notifyOfflineUser,
      updateConversationStatus,
      ...(role === "no-approval" ? {} : { approval }),
    },
  } as unknown as CanUseToolContext;
  const call = (tool: string, input: Record<string, unknown>) =>
    createCanUseTool(ctx)(tool, input, { signal: opts.callSignal ?? new AbortController().signal, toolUseID: "t", requestId: "r" } as never) as Promise<{
      behavior: string;
      message?: string;
    }>;
  const cards = () => sendToClient.mock.calls.filter((c) => (c as unknown[])[1] && ((c as unknown[])[1] as { type?: string }).type === "review_gate");
  return { call, viewerRole, abortableReviewGate, sendToClient, notifyOfflineUser, updateConversationStatus, cards };
}

const push = () => SAMPLES[TOOLS.pushBranch].input;

describe("legacy push fallback: only the Owner may answer the in-memory card (#12197 D1)", () => {
  test("the constant names the push tool", () => {
    expect(GITHUB_PUSH_BRANCH_TOOL).toBe(TOOLS.pushBranch);
  });

  test("Owner: the card is emitted and the answer is honoured", async () => {
    const h = setup("owner");
    const res = await h.call(TOOLS.pushBranch, push());
    expect(h.viewerRole).toHaveBeenCalledTimes(1);
    expect(h.cards()).toHaveLength(1);
    expect(h.abortableReviewGate).toHaveBeenCalledTimes(1);
    expect(res.behavior).toBe("allow");
    expect(reports).toEqual([]);
  });

  test("member: static deny, no card, no status write, no offline notification", async () => {
    const h = setup("member");
    const res = await h.call(TOOLS.pushBranch, push());
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.sendToClient).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(h.notifyOfflineUser).not.toHaveBeenCalled();
    expect(h.updateConversationStatus).not.toHaveBeenCalled();
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ decision: "platform-gate-push-owner-required", role: "member" }),
      expect.any(String),
    );
  });

  test("member, and the flag read throws (an error is OFF): static deny, no card", async () => {
    const h = setup("member-flag-throws");
    const res = await h.call(TOOLS.pushBranch, push());
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.viewerRole).toHaveBeenCalledTimes(1);
    expect(h.sendToClient).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("the role read throws: static deny, no card, and viewerRoleFailed is reported with its stage", async () => {
    const h = setup("throws");
    const res = await h.call(TOOLS.pushBranch, push());
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.sendToClient).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reports).toHaveLength(1);
    expect(reports[0][0]).toBe("viewerRoleFailed");
    expect(reports[0][2]).toEqual(
      expect.objectContaining({ tags: { stage: "legacy-push-owner-check" }, workspaceId: WORKSPACE_ID, extra: { outcome: "denied-no-card" } }),
    );
  });

  test("Stop pressed while the role is read (an Owner answer arrives after): denied as aborted, no card, no notification, no status write, no report", async () => {
    const call = new AbortController();
    const h = setup("owner", {
      callSignal: call.signal,
      viewerRole: () =>
        new Promise((resolve) => {
          call.abort();
          setTimeout(() => resolve("owner"), 0);
        }),
    });
    const res = await h.call(TOOLS.pushBranch, push());
    expect(res.behavior).toBe("deny");
    expect(res.message).not.toBe(APPROVAL_UNAVAILABLE_DENY);
    expect(h.sendToClient).not.toHaveBeenCalled();
    expect(h.notifyOfflineUser).not.toHaveBeenCalled();
    expect(h.updateConversationStatus).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
    expect(reports).toEqual([]);
  });

  test("a role read that never settles ends at the deadline: static deny, no card, viewerRoleFailed reported", async () => {
    vi.useFakeTimers();
    try {
      const h = setup("owner", { viewerRole: () => new Promise(() => {}) });
      const pending = h.call(TOOLS.pushBranch, push());
      await vi.advanceTimersByTimeAsync(PUSH_ROLE_READ_DEADLINE_MS + 1);
      const res = await pending;
      expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
      expect(h.sendToClient).not.toHaveBeenCalled();
      expect(reports.map((r) => r[0])).toEqual(["viewerRoleFailed"]);
    } finally {
      vi.useRealTimers();
    }
  });

  test("no approval dependency: static deny, no card", async () => {
    const h = setup("no-approval");
    const res = await h.call(TOOLS.pushBranch, push());
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(h.sendToClient).not.toHaveBeenCalled();
    expect(h.abortableReviewGate).not.toHaveBeenCalled();
  });

  test("narrow scope: email_send with a member still gets the in-memory card (ADR-309 legacy divergence)", async () => {
    const h = setup("member");
    const res = await h.call(TOOLS.emailSend, SAMPLES[TOOLS.emailSend].input);
    expect(h.viewerRole).not.toHaveBeenCalled();
    expect(h.cards()).toHaveLength(1);
    expect(res.behavior).toBe("allow");
  });
});
