/**
 * #4672 R1: a deny never leaves an execution grant behind, on EVERY deny path of the gate.
 *
 * The older test in gate-flow.test.ts ("a consume rejection, a cap and an aborted call never write a grant") covers the
 * live-consume rejection, the cap and an abort. The Guard 1 mutation battery found that writing a grant on the
 * re-proposal consume rejection (`submit` answers `consume_rejected`) survived it, as would the other submit outcomes and
 * the terminal wait outcomes. A grant that outlives a deny would let a later handler call (the SDK never executed the
 * denied one, but a model-made call with the same arguments could) run without a fresh approval for up to 120 s.
 * Calls `runApprovalGate` directly with a fake dependency; the session is `enforcing` after every one of these.
 */
import { describe, expect, test, vi } from "vitest";

vi.mock("@/server/logger", () => ({ createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }), default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { runApprovalGate } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import type { SubmitResult } from "@/server/approval/service";
import type { WaitStatus } from "@/server/approval/waiters";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const row = (status: string) => ({
  id: "00000000-0000-4000-8000-000000000006",
  workspace_id: WORKSPACE_ID,
  conversation_id: CONVERSATION_ID,
  requested_by_user_id: USER_ID,
  tool_name: TOOLS.pushBranch,
  action_sha256: "a".repeat(64),
  status: status as never,
  expires_at: new Date(Date.now() + 3600_000).toISOString(),
  decided_at: null,
  decided_by: null,
  consumed_at: null,
  expired_at: null,
  revoked_at: null,
  revoked_by: null,
  unanswered_flagged_at: null,
  created_at: new Date().toISOString(),
  canonical_action: null,
});

const wait = (): SubmitResult => ({
  kind: "wait",
  approval: row("pending"),
  created: true,
  requestCount: 1,
  notify: true,
  expiresAt: row("pending").expires_at,
});

async function run(submit: SubmitResult, readStatus: WaitStatus | null = null) {
  const grants = new ExecutionGrants();
  const allow = vi.fn((input: Record<string, unknown>) => ({ behavior: "allow" as const, updatedInput: input }));
  const approval: ApprovalGateDeps = {
    isEnabled: async () => true,
    workspaceId: WORKSPACE_ID,
    grants,
    resolveServerDerived: async (t) => SAMPLES[t].server as Record<string, string>,
    submit: async () => submit,
    readStatus: async () => readStatus,
    consume: async () => ({ consumed: false, reason: "hash_mismatch" }),
    viewerRole: async () => "owner",
    waitOptions: { deadlineMs: 30, sleep: (ms) => new Promise((r) => setTimeout(r, Math.min(ms, 5))) },
  };
  const res = await runApprovalGate({
    toolName: TOOLS.pushBranch,
    toolInput: structuredClone(SAMPLES[TOOLS.pushBranch].input),
    callSignal: undefined,
    controllerSignal: new AbortController().signal,
    userId: USER_ID,
    conversationId: CONVERSATION_ID,
    approval,
    sendToClient: () => true,
    hold: async (_id, _signal, w) => w(),
    allow,
    logDecision: () => undefined,
  });
  return { res, grants, allow };
}

describe("a deny writes no execution grant (every deny path of the gate)", () => {
  const CASES: Array<[string, SubmitResult, WaitStatus | null]> = [
    ["re-proposal consume rejected (submit answers consume_rejected)", { kind: "consume_rejected", approvalId: "x", reason: "hash_mismatch" }, null],
    ["re-proposal consume rejected because the principals changed", { kind: "consume_rejected", approvalId: "x", reason: "decider_not_owner" }, null],
    ["request not waitable (neither pending nor approved)", { kind: "not_waitable", approval: row("rejected"), requestCount: 1 }, null],
    ["pending cap reached", { kind: "cap_reached", scope: "conversation" }, null],
    ["Owner rejected while the agent waited", wait(), "rejected"],
    ["expired while the agent waited", wait(), "expired"],
    ["another identical call consumed it first", wait(), "consumed"],
    ["nobody decided before the wait deadline", wait(), null],
  ];

  test.each(CASES)("%s: deny, no allow(), no grant, session enforcing", async (_name, submit, read) => {
    const { res, grants, allow } = await run(submit, read);
    expect(res?.behavior).toBe("deny");
    expect(allow).not.toHaveBeenCalled();
    expect(grants.size()).toBe(0);
    expect(grants.enforcing).toBe(true);
  });

  test("control: the released (re-proposal) path DOES write exactly one grant, so the assertions above are not vacuous", async () => {
    const { res, grants, allow } = await run({ kind: "released", approvalId: "x", requestCount: 2 });
    expect(res?.behavior).toBe("allow");
    expect(allow).toHaveBeenCalledTimes(1);
    expect(grants.size()).toBe(1);
  });
});
