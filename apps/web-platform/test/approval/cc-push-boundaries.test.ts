/**
 * #11636 (ADR-309): the isolation boundaries around the cc push registration that the dispatcher-level and gate-level suites
 * do not pin. Small and dispatcher-free (no cc-dispatcher import).
 *
 *  (a) the push FQN does not match any PreToolUse hook matcher in agent-runner-query-options.ts (a hook `allow` would
 *      resolve ahead of `canUseTool`, i.e. ahead of the gate), and a synthetic name that DOES match is detected, so the
 *      pin cannot pass vacuously;
 *  (b) two factory invocations never share a grants object: covered next to the live factory in
 *      cc-dispatcher-real-factory.test.ts ("github_push_branch registration", distinct grants per invocation);
 *  (c) conversation B cannot consume conversation A's approved row: the gate-deps `consume` hands the CALLING
 *      conversation to the `consume_approval` RPC, and the action hash binds the conversation;
 *  (d) registered on the cold build, flag turned off later: the next gated call is refused with the static unavailable text
 *      and no card (the load-bearing per-call re-check; registration is policy, not authorization).
 *
 * Synthesized data only.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { log } = vi.hoisted(() => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));

import { createCanUseTool, type CanUseToolContext } from "@/server/permission-callback";
import { APPROVAL_UNAVAILABLE_DENY } from "@/server/approval/gate-flow";
import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { createApprovalGateDeps } from "@/server/approval/gate";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants } from "@/server/approval/grants";
import { clearAllWaiters } from "@/server/approval/waiters";
import { stripComments } from "./source-scan";
import { CONVERSATION_ID, OTHER_CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const PUSH = TOOLS.pushBranch;

beforeEach(() => {
  clearAllWaiters();
  vi.clearAllMocks();
  process.env.SENTRY_USERID_PEPPER = "cc-push-boundaries-test-pepper";
});

describe("(a) the push FQN is not pre-allowed by a PreToolUse hook matcher", () => {
  const src = stripComments(readFileSync(join(__dirname, "../../server/agent-runner-query-options.ts"), "utf8"));
  const matchers = [...src.matchAll(/matcher:\s*"([^"]+)"/g)].map((m) => m[1]);
  // A hook matcher is a regex tested against the tool name, UNANCHORED (a substring hit counts).
  const hits = (name: string) => matchers.filter((m) => new RegExp(m).test(name));

  test("the scan is non-vacuous: it finds the sandbox matcher and the other per-tool matchers", () => {
    expect(matchers.length).toBeGreaterThanOrEqual(3);
    expect(matchers.some((m) => m.includes("Bash") && m.includes("Read"))).toBe(true);
  });

  test("no hook matcher matches the push FQN", () => {
    expect(hits(PUSH)).toEqual([]);
  });

  test("a synthetic name that does match the sandbox matcher IS detected (the pin cannot pass vacuously)", () => {
    expect(hits("mcp__soleur_platform__Bash_push").length).toBeGreaterThan(0);
    expect(hits("Bash").length).toBeGreaterThan(0);
  });
});

describe("(c) conversation B cannot consume conversation A's approved row", () => {
  const A = CONVERSATION_ID;
  const B = OTHER_CONVERSATION_ID;
  const action = (conv: string) =>
    computeActionHash({
      toolName: PUSH,
      workspaceId: WORKSPACE_ID,
      conversationId: conv,
      action: canonicalizeAction(PUSH, SAMPLES[PUSH].input, SAMPLES[PUSH].server),
    });

  test("the action hash binds the conversation: the same action in conversation B hashes differently", () => {
    expect(action(A)).not.toBe(action(B));
    expect(action(A)).toBe(action(A));
  });

  test("consume hands the CALLING conversation to the database; the database (faked here) consumes only for the row's conversation, once", async () => {
    const hash = action(A);
    let status = "approved";
    const rpc = vi.fn(async (fn: string, args?: Record<string, unknown>) => {
      expect(fn).toBe("consume_approval");
      if (args?.p_conversation !== A) return { data: { consumed: false, reason: "conversation_mismatch" }, error: null };
      if (status !== "approved") return { data: { consumed: false, reason: "not_approved" }, error: null };
      status = "consumed";
      return { data: { consumed: true }, error: null };
    });
    const deps = createApprovalGateDeps({
      userId: USER_ID,
      workspaceId: WORKSPACE_ID,
      repoSlug: "example-org/example-repo",
      workspacePath: "/tmp/ws",
      grants: new ExecutionGrants(),
      serviceClient: () => ({ rpc }),
    });
    const asB = await deps.consume({ id: "approval-1", hash, conversationId: B });
    expect(asB).toEqual({ consumed: false, reason: "conversation_mismatch" });
    expect(rpc.mock.calls[0][1]).toMatchObject({ p_id: "approval-1", p_hash: hash, p_conversation: B });
    expect(status).toBe("approved"); // B did not spend A's approval
    expect(await deps.consume({ id: "approval-1", hash, conversationId: A })).toEqual({ consumed: true });
    expect(await deps.consume({ id: "approval-1", hash, conversationId: A })).toEqual({ consumed: false, reason: "not_approved" });
  });
});

describe("(d) registered on the cold build, flag turned off later: the next gated call is refused", () => {
  test("flag ON runs the flow (enforcing turns on); flag then OFF: static unavailable deny, no card, no flow", async () => {
    let flag = true;
    const grants = new ExecutionGrants();
    const submit = vi.fn(async () => ({ kind: "cap_reached" as const, scope: "conversation" as const }));
    const approval = {
      isEnabled: async () => flag,
      workspaceId: WORKSPACE_ID,
      grants,
      resolveServerDerived: async (t: string) => SAMPLES[t].server as Record<string, string>,
      submit,
      readStatus: vi.fn(),
      consume: vi.fn(),
      viewerRole: async () => "owner" as const,
    } as unknown as ApprovalGateDeps;
    const abortableReviewGate = vi.fn(() => Promise.resolve("Approve"));
    const sendToClient = vi.fn((_userId: string, _msg: unknown) => true);
    const ctx = {
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      leaderId: "cto",
      workspacePath: "/tmp/ws",
      platformToolNames: [PUSH],
      pluginMcpServerNames: [],
      repoOwner: "",
      repoName: "",
      session: { abort: new AbortController(), reviewGateResolvers: new Map(), sessionId: null },
      controllerSignal: new AbortController().signal,
      deps: { abortableReviewGate, sendToClient, notifyOfflineUser: vi.fn().mockResolvedValue(true), updateConversationStatus: vi.fn(async () => {}), approval, approvalFailClosed: true },
    } as unknown as CanUseToolContext;
    const canUseTool = createCanUseTool(ctx);
    const call = () =>
      canUseTool(PUSH, { ...SAMPLES[PUSH].input }, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never) as Promise<{
        behavior: string;
        message?: string;
      }>;

    await call();
    expect(submit).toHaveBeenCalledTimes(1); // the flow ran
    expect(grants.enforcing).toBe(true);

    flag = false;
    submit.mockClear();
    const res = await call();
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(submit).not.toHaveBeenCalled();
    expect(abortableReviewGate).not.toHaveBeenCalled();
    expect(sendToClient.mock.calls.some((c) => (c[1] as { type?: string })?.type === "review_gate")).toBe(false);
    expect(sendToClient.mock.calls.some((c) => (c[1] as { type?: string })?.type === "approval_request")).toBe(false);
  });
});
