/**
 * #9601: the FIRST send of the approval card (gate-flow.ts) carries the requester key only as the literal "you".
 *
 * The first send always goes to the session user whose own agent proposed the action, so it keeps the full view (the
 * documented exception to the reattach redaction). The only label is `"you"` for the verified requester; any other
 * viewer, Owner or member, gets no `requester` key, and the gate never reads another member's identity (it has no
 * labeler dependency at all). Own file so no existing named gate test is touched.
 */
import { describe, expect, test, vi } from "vitest";

vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }), default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { canonicalizeAction } from "@/server/approval/canonical";
import { runApprovalGate } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { renderApprovalView } from "@/server/approval/render";
import type { SubmitResult } from "@/server/approval/service";
import { clearAllWaiters } from "@/server/approval/waiters";
import type { WSMessage } from "@/lib/types";
import { APPROVAL_ID, CONVERSATION_ID, OTHER_MEMBER_ID, OWNER_ID, REQUESTER_ID, SAMPLES, TOOLS, WORKSPACE_ID } from "./fixtures";

type ApprovalFrame = Extract<WSMessage, { type: "approval_request" }>;

interface Opts {
  /** The session user (the viewer of the first send). */
  userId: string;
  viewerRole: "owner" | "member";
  /** The stored requester of the live row. */
  requestedBy: string | null;
}

async function runGate(o: Opts) {
  process.env.SENTRY_USERID_PEPPER = "gate-requester-test-pepper";
  clearAllWaiters();
  const tool = TOOLS.emailSend;
  const input = structuredClone(SAMPLES[tool].input) as Record<string, unknown>;
  const frames: WSMessage[] = [];
  const approval: ApprovalGateDeps = {
    isEnabled: async () => true,
    workspaceId: WORKSPACE_ID,
    grants: new ExecutionGrants(),
    resolveServerDerived: async () => undefined,
    submit: async (p) =>
      ({
        kind: "wait",
        approval: {
          id: APPROVAL_ID,
          workspace_id: WORKSPACE_ID,
          conversation_id: CONVERSATION_ID,
          requested_by_user_id: o.requestedBy,
          tool_name: tool,
          action_sha256: p.actionSha256,
          status: "pending",
          expires_at: "2031-01-02T03:04:05.000Z",
          created_at: new Date().toISOString(),
        } as never,
        created: false,
        requestCount: 2,
        notify: false,
        expiresAt: "2031-01-02T03:04:05.000Z",
      }) satisfies SubmitResult,
    readStatus: async () => "rejected",
    consume: async () => ({ consumed: false, reason: "unknown" }),
    viewerRole: async () => o.viewerRole,
  };
  const verdict = await runApprovalGate({
    toolName: tool,
    toolInput: input,
    callSignal: undefined,
    controllerSignal: new AbortController().signal,
    userId: o.userId,
    conversationId: CONVERSATION_ID,
    approval,
    sendToClient: (_u, payload) => {
      frames.push(payload);
      return true;
    },
    hold: async (_id, _signal, wait) => wait(),
    allow: (i) => ({ behavior: "allow", updatedInput: i }),
    logDecision: () => undefined,
  });
  const card = frames.find((f): f is ApprovalFrame => f.type === "approval_request");
  return { tool, input, frames, card, verdict };
}

describe("first send: the requester key", () => {
  test("an Owner who is the requester: the literal you", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: OWNER_ID });
    expect(card?.requester).toBe("you");
  });

  test("a member who is the requester: the literal you, and the full view", async () => {
    const { card, tool, input } = await runGate({ userId: REQUESTER_ID, viewerRole: "member", requestedBy: REQUESTER_ID });
    expect(card?.requester).toBe("you");
    expect(card?.view).toEqual(renderApprovalView(canonicalizeAction(tool, input, undefined)));
  });

  test("an Owner viewer where the live row was raised by another member: no requester key (no lookup exists on the first send)", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID });
    expect(card).toBeDefined();
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("an Owner viewer and a NULL requester: no requester key", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: null });
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("a member viewer where the row was raised by another member: the full view (first-send exception), no requester key", async () => {
    const { card, tool, input } = await runGate({ userId: OTHER_MEMBER_ID, viewerRole: "member", requestedBy: REQUESTER_ID });
    expect(card).toBeDefined();
    expect(card?.view).toEqual(renderApprovalView(canonicalizeAction(tool, input, undefined)));
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("the requester key is the LAST property of the frame (the Guard-1 anchors sit on the neighbouring lines)", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: OWNER_ID });
    const keys = Object.keys(card!);
    expect(keys.at(-1)).toBe("requester");
    expect(keys.slice(-2, -1)).toEqual(["agentWaiting"]);
  });
});
