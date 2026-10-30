/**
 * #4672 P2-5 (test-design review): the server-derived resolver must be handed the SNAPSHOT, never the live tool input.
 *
 * Why it matters: `email_reply` derives the recipient from `messageId`. If the resolver read the live input and the agent
 * swapped `messageId` to B while the resolver awaited, the recipient would be B's sender while the hashed `messageId`
 * is A: the Owner approves "reply to B's sender" and the handler runs A. The older test in gate-flow.test.ts ("a mutation
 * made between the snapshot and the hash ...") mutates the live object from inside a resolver that IGNORES its argument,
 * so passing `a.toolInput` to the resolver instead of `snapshot` survived. This test makes the resolver record its
 * argument and asserts, after the live object was mutated, that the argument is an unmutated copy and not the live
 * reference. Calls `runApprovalGate` directly with a minimal fake dependency (no database).
 */
import { describe, expect, test, vi } from "vitest";

vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }), default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { runApprovalGate } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

describe("the server-derived resolver is handed the snapshot, not the live input (P2-5)", () => {
  test.each([
    [TOOLS.emailReply, "messageId", "00000000-0000-4000-8000-0000000000ff"],
    [TOOLS.pushBranch, "branch", "attacker-branch"],
  ])("%s: resolveServerDerived receives the snapshot, not the live input", async (tool, field, swapped) => {
    const live = structuredClone(SAMPLES[tool].input) as Record<string, unknown>;
    const original = structuredClone(live);
    const received: Array<{ tool: string; arg: Record<string, unknown> }> = [];
    const submitted: string[] = [];

    const approval: ApprovalGateDeps = {
      isEnabled: async () => true,
      workspaceId: WORKSPACE_ID,
      grants: new ExecutionGrants(),
      resolveServerDerived: async (t, arg) => {
        received.push({ tool: t, arg });
        // The agent swaps a bound field while the platform is resolving the server-derived fields.
        live[field] = swapped;
        await new Promise((r) => setTimeout(r, 5));
        return SAMPLES[tool].server as Record<string, string>;
      },
      // Stop the flow right after the hash: a cap is a deny, so nothing waits or is allowed.
      submit: async (p) => {
        submitted.push(p.actionSha256);
        return { kind: "cap_reached", scope: "workspace" };
      },
      readStatus: async () => null,
      consume: async () => ({ consumed: false, reason: "unknown" }),
      viewerRole: async () => "owner",
    };

    const res = await runApprovalGate({
      toolName: tool,
      toolInput: live,
      callSignal: undefined,
      controllerSignal: new AbortController().signal,
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      approval,
      sendToClient: () => true,
      hold: async (_id, _signal, wait) => wait(),
      allow: (input) => ({ behavior: "allow", updatedInput: input }),
      logDecision: () => undefined,
    });

    // The flow reached the resolver exactly once, for this tool.
    expect(res?.behavior).toBe("deny");
    expect(received).toHaveLength(1);
    expect(received[0].tool).toBe(tool);
    // The live object WAS mutated (the scenario is real) ...
    expect(live[field]).toBe(swapped);
    expect(live).not.toEqual(original);
    // ... and the resolver never saw it: its argument is an unmutated copy, not the live reference.
    expect(received[0].arg).not.toBe(live);
    expect(received[0].arg).toEqual(original);
    // The hash that went to the database binds the ORIGINAL input.
    const expected = computeActionHash({
      toolName: tool,
      workspaceId: WORKSPACE_ID,
      conversationId: CONVERSATION_ID,
      action: canonicalizeAction(tool, original, SAMPLES[tool].server),
    });
    expect(submitted).toEqual([expected]);
  });

  test("the resolver's argument is also detached from the live object for a nested mutation", async () => {
    const tool = TOOLS.emailReply;
    const live = structuredClone(SAMPLES[tool].input) as Record<string, unknown>;
    const original = structuredClone(live);
    let seen: Record<string, unknown> | undefined;
    const approval: ApprovalGateDeps = {
      isEnabled: async () => true,
      workspaceId: WORKSPACE_ID,
      grants: new ExecutionGrants(),
      resolveServerDerived: async (_t, arg) => {
        seen = arg;
        (live as { art14?: Record<string, unknown> }).art14 = { identity: "swapped" };
        return SAMPLES[tool].server as Record<string, string>;
      },
      submit: async () => ({ kind: "cap_reached", scope: "conversation" }),
      readStatus: async () => null,
      consume: async () => ({ consumed: false, reason: "unknown" }),
      viewerRole: async () => "owner",
    };
    await runApprovalGate({
      toolName: tool,
      toolInput: live,
      callSignal: undefined,
      controllerSignal: new AbortController().signal,
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      approval,
      sendToClient: () => true,
      hold: async (_id, _signal, wait) => wait(),
      allow: (input) => ({ behavior: "allow", updatedInput: input }),
      logDecision: () => undefined,
    });
    expect(seen).toEqual(original);
    expect(seen).not.toBe(live);
  });
});
