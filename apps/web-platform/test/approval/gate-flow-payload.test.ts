/**
 * #4672 (ADR-307), round-2 test-design FD-6: the PAYLOAD wiring of the gate flow, pinned field by field.
 *
 * Every other gate test asserts the verdict and the frame TYPES. Two fields survived being swapped for a wrong value:
 * `requestedByUserId` (the member whose principal status the consume re-checks) and the card's `expiresAt` (the
 * countdown the Owner sees). The first fails loud only in production (the consume's member re-check), the second is
 * silent. This file hands the flow distinct, recognisable values for each source and asserts each lands where it
 * belongs: the submitted request, the card frame, and the `onRequested` dispatch (which takes the DATABASE's `expiresAt`,
 * a different field from the row's own `expires_at` on the card).
 *
 * Calls `runApprovalGate` directly with a minimal fake dependency (no database). Synthesized data only.
 */
import { describe, expect, test, vi } from "vitest";

vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }), default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { runApprovalGate } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import type { CreateApprovalParams, SubmitResult } from "@/server/approval/service";
import { clearAllWaiters } from "@/server/approval/waiters";
import type { WSMessage } from "@/lib/types";
import { APPROVAL_ID, CONVERSATION_ID, OTHER_WORKSPACE_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const CARD_EXPIRES = "2031-01-02T03:04:05.000Z";
const DISPATCH_EXPIRES = "2032-06-07T08:09:10.000Z";

async function run() {
  process.env.SENTRY_USERID_PEPPER = "gate-payload-test-pepper";
  clearAllWaiters();
  const tool = TOOLS.emailSend;
  const input = structuredClone(SAMPLES[tool].input) as Record<string, unknown>;
  const submitted: CreateApprovalParams[] = [];
  const dispatched: Array<{ approvalId: string; created: boolean; notify: boolean; expiresAt: string }> = [];
  const frames: WSMessage[] = [];
  const approval: ApprovalGateDeps = {
    isEnabled: async () => true,
    workspaceId: WORKSPACE_ID,
    grants: new ExecutionGrants(),
    resolveServerDerived: async () => undefined,
    submit: async (p) => {
      submitted.push(p);
      const r: SubmitResult = {
        kind: "wait",
        approval: {
          id: APPROVAL_ID,
          workspace_id: WORKSPACE_ID,
          conversation_id: CONVERSATION_ID,
          requested_by_user_id: USER_ID,
          tool_name: tool,
          action_sha256: p.actionSha256,
          status: "pending",
          expires_at: CARD_EXPIRES,
          created_at: new Date().toISOString(),
        } as never,
        created: true,
        requestCount: 3,
        notify: true,
        expiresAt: DISPATCH_EXPIRES,
      };
      return r;
    },
    readStatus: async () => "rejected",
    consume: async () => ({ consumed: false, reason: "unknown" }),
    viewerRole: async () => "member",
    onRequested: async (p) => {
      dispatched.push(p);
    },
  };
  const verdict = await runApprovalGate({
    toolName: tool,
    toolInput: input,
    callSignal: undefined,
    controllerSignal: new AbortController().signal,
    userId: USER_ID,
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
  return { tool, input, submitted, dispatched, frames, verdict };
}

describe("gate-flow payload wiring", () => {
  test("the submitted request carries the REQUESTING user (not the conversation or the workspace), the workspace, the conversation, the tool, the hash and the canonical action", async () => {
    const { tool, input, submitted } = await run();
    expect(submitted).toHaveLength(1);
    const p = submitted[0];
    // Three different uuids: a swap between any two of them cannot pass.
    expect(new Set([USER_ID, CONVERSATION_ID, WORKSPACE_ID, OTHER_WORKSPACE_ID]).size).toBe(4);
    expect(p.requestedByUserId).toBe(USER_ID);
    expect(p.workspaceId).toBe(WORKSPACE_ID);
    expect(p.conversationId).toBe(CONVERSATION_ID);
    expect(p.toolName).toBe(tool);
    const action = canonicalizeAction(tool, input, undefined);
    expect(p.canonicalAction).toEqual(action);
    expect(p.actionSha256).toBe(computeActionHash({ toolName: tool, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action }));
  });

  test("the approval_request card carries the row's own expires_at, the request count, the viewer role and a waiting agent", async () => {
    const { frames } = await run();
    const cards = frames.filter((f) => f.type === "approval_request");
    expect(cards).toHaveLength(1);
    expect(cards[0]).toMatchObject({
      type: "approval_request",
      approvalId: APPROVAL_ID,
      conversationId: CONVERSATION_ID,
      status: "pending",
      expiresAt: CARD_EXPIRES,
      requestCount: 3,
      viewerRole: "member",
      agentWaiting: true,
    });
  });

  test("the onRequested dispatch gets the approval id, the created and notify verdicts and the DATABASE's expiresAt (not the card's)", async () => {
    const { dispatched } = await run();
    expect(dispatched).toEqual([{ approvalId: APPROVAL_ID, created: true, notify: true, expiresAt: DISPATCH_EXPIRES }]);
  });

  test("the flow ends as designed for this fixture (Owner rejection -> deny), so the payload assertions above ran on the real path", async () => {
    const { verdict } = await run();
    expect(verdict).toMatchObject({ behavior: "deny" });
  });
});
