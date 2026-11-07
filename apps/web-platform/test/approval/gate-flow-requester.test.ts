/**
 * #9601: the FIRST send of the approval card (gate-flow.ts) names the requester for an Owner viewer.
 *
 * The first send always goes to the session user whose own agent proposed the action, so it keeps the full view (the
 * documented exception to the reattach redaction). The label is `"you"` for the verified requester (no read), the
 * labeler's value for an Owner viewer whose live row was raised by another member, and absent otherwise. The lookup is
 * bounded: a hung read never delays the card while the agent waits. Own file so no existing named gate test is touched.
 */
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }), default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { canonicalizeAction } from "@/server/approval/canonical";
import { runApprovalGate } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { renderApprovalView } from "@/server/approval/render";
import type { SubmitResult } from "@/server/approval/service";
import { clearAllWaiters } from "@/server/approval/waiters";
import type { RequesterLabelFn } from "@/server/approval/card-visibility";
import type { WSMessage } from "@/lib/types";
import { APPROVAL_ID, CONVERSATION_ID, OTHER_MEMBER_ID, OWNER_ID, REQUESTER_EMAIL, REQUESTER_ID, SAMPLES, TOOLS, WORKSPACE_ID } from "./fixtures";

type ApprovalFrame = Extract<WSMessage, { type: "approval_request" }>;

interface Opts {
  /** The session user (the viewer of the first send). */
  userId: string;
  viewerRole: "owner" | "member";
  /** The stored requester of the live row. */
  requestedBy: string | null;
  /** Omit to model a harness with no `requesterLabel` dep. */
  requesterLabel?: RequesterLabelFn;
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
    ...(o.requesterLabel ? { requesterLabel: o.requesterLabel } : {}),
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

afterEach(() => {
  vi.useRealTimers();
});

describe("first send: the requester label", () => {
  test("an Owner who is the requester: the literal you, and no lookup", async () => {
    const label = vi.fn(async () => REQUESTER_EMAIL);
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: OWNER_ID, requesterLabel: label });
    expect(card?.requester).toBe("you");
    expect(label).not.toHaveBeenCalled();
  });

  test("a member who is the requester: the literal you, full view, and no lookup", async () => {
    const label = vi.fn(async () => REQUESTER_EMAIL);
    const { card, tool, input } = await runGate({ userId: REQUESTER_ID, viewerRole: "member", requestedBy: REQUESTER_ID, requesterLabel: label });
    expect(card?.requester).toBe("you");
    expect(card?.view).toEqual(renderApprovalView(canonicalizeAction(tool, input, undefined)));
    expect(label).not.toHaveBeenCalled();
  });

  test("an Owner viewer where the live row was raised by another member: the labeler's value, asked with the ROW's workspace", async () => {
    const label = vi.fn(async () => REQUESTER_EMAIL);
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID, requesterLabel: label });
    expect(card?.requester).toBe(REQUESTER_EMAIL);
    expect(label).toHaveBeenCalledTimes(1);
    expect(label).toHaveBeenCalledWith(WORKSPACE_ID, OWNER_ID, REQUESTER_ID);
  });

  test("an Owner viewer and a NULL requester: the labeler is asked and its fallback is shown", async () => {
    const label = vi.fn(async () => "a workspace member");
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: null, requesterLabel: label });
    expect(label).toHaveBeenCalledWith(WORKSPACE_ID, OWNER_ID, null);
    expect(card?.requester).toBe("a workspace member");
  });

  test("a member viewer where the row was raised by another member: the full view (first-send exception), no requester key, no lookup", async () => {
    const label = vi.fn(async () => REQUESTER_EMAIL);
    const { card, tool, input } = await runGate({ userId: OTHER_MEMBER_ID, viewerRole: "member", requestedBy: REQUESTER_ID, requesterLabel: label });
    expect(card).toBeDefined();
    expect(card?.view).toEqual(renderApprovalView(canonicalizeAction(tool, input, undefined)));
    expect(Object.hasOwn(card!, "requester")).toBe(false);
    expect(label).not.toHaveBeenCalled();
  });

  test("a failed role read (viewer falls back to member) never asks the labeler", async () => {
    const label = vi.fn(async () => REQUESTER_EMAIL);
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "member", requestedBy: REQUESTER_ID, requesterLabel: label });
    expect(label).not.toHaveBeenCalled();
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("the labeler throws: the frame is still sent, the key is omitted", async () => {
    const label = vi.fn(async () => {
      throw new Error("lookup exploded");
    });
    const { card, verdict } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID, requesterLabel: label });
    expect(card).toBeDefined();
    expect(card?.view).not.toBeNull();
    expect(Object.hasOwn(card!, "requester")).toBe(false);
    expect(verdict).toMatchObject({ behavior: "deny" });
  });

  test("the labeler returns undefined: no key", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID, requesterLabel: async () => undefined });
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("no requesterLabel dep (every existing harness): an Owner viewer and another requester gets no key", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID });
    expect(card).toBeDefined();
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("the requester key is the LAST property of the frame (the Guard-1 anchors sit on the neighbouring lines)", async () => {
    const { card } = await runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: OWNER_ID, requesterLabel: async () => REQUESTER_EMAIL });
    const keys = Object.keys(card!);
    expect(keys.at(-1)).toBe("requester");
    expect(keys.slice(-2, -1)).toEqual(["agentWaiting"]);
  });
});

describe("first send: the lookup is bounded", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  test("a labeler that never resolves does not hold the card past the deadline; the frame has no key", async () => {
    const label = vi.fn(() => new Promise<string | undefined>(() => {}));
    const p = runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID, requesterLabel: label });
    await vi.advanceTimersByTimeAsync(2_500);
    const { card } = await p;
    expect(label).toHaveBeenCalledTimes(1);
    expect(card).toBeDefined();
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });

  test("a labeler that resolves late does not mutate the frame that was already sent", async () => {
    let resolveLate: (v: string) => void = () => {};
    const label = vi.fn(() => new Promise<string | undefined>((r) => (resolveLate = r)));
    const p = runGate({ userId: OWNER_ID, viewerRole: "owner", requestedBy: REQUESTER_ID, requesterLabel: label });
    await vi.advanceTimersByTimeAsync(2_500);
    const { card } = await p;
    resolveLate(REQUESTER_EMAIL);
    await vi.advanceTimersByTimeAsync(10);
    expect(Object.hasOwn(card!, "requester")).toBe(false);
  });
});
