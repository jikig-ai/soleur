/**
 * #11636 (ADR-309): the cc shape of the approval flow for the one tool the cc dispatcher now registers,
 * `github_push_branch`. The REAL `createCanUseTool` (cc-shaped deps: `approvalFailClosed: true`, `platformToolNames` naming
 * the push FQN) runs against a hand-built `ApprovalGateDeps` over the shared fixtures, and the REAL builder
 * (`buildGithubPushBranchTool`, `requireGrant: true`) shares the SAME grants object, with `pushBranch` mocked.
 *
 * Only what is new for cc is asserted here: the approved push runs exactly the approved commit; a denied or undecided push
 * runs nothing and its deny text carries no tool input; the durable surfaces (the `approval_request` frame, the
 * `onRequested` push/email dispatch) are exercised, including for a non-Owner requester; a handler called after a deny
 * finds no grant. The gate's own texts for expired, consume-rejected and aborted verdicts are covered by gate-flow*.test.ts
 * and flag-off / unreadable-flag denies for this tool by cc-approval-fail-closed.test.ts (cited, not repeated).
 *
 * Synthesized data only.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  pushBranch: vi.fn(),
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => h.log, default: h.log }));
vi.mock("@/server/permission-log", () => ({ logPermissionDecision: vi.fn() }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn((name: string, description: string, schema: unknown, handler: Function) => ({ name, description, schema, handler })),
}));
vi.mock("@/server/github-read-tools", () => ({}));
vi.mock("@/server/ci-tools", () => ({}));
vi.mock("@/server/github-app", () => ({}));
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: h.pushBranch }));

import { createCanUseTool, type CanUseToolContext } from "@/server/permission-callback";
import { APPROVAL_PENDING_DENY, APPROVAL_REJECTED_DENY } from "@/server/approval/gate-flow";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import { ExecutionGrants, GRANT_MISSING_MESSAGE } from "@/server/approval/grants";
import type { SubmitResult } from "@/server/approval/service";
import type { WaitStatus } from "@/server/approval/waiters";
import { clearAllWaiters } from "@/server/approval/waiters";
import { buildGithubPushBranchTool } from "@/server/github-tools";
import { CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const PUSH = TOOLS.pushBranch;
const INPUT = SAMPLES[PUSH].input as { branch: string; force: boolean };
const SHA = (SAMPLES[PUSH].server as { headSha: string }).headSha;
const APPROVAL_ID = "00000000-0000-4000-8000-000000000006";

const row = (status: string) => ({
  id: APPROVAL_ID,
  workspace_id: WORKSPACE_ID,
  conversation_id: CONVERSATION_ID,
  requested_by_user_id: USER_ID,
  tool_name: PUSH,
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

const waitRequest = (): SubmitResult => ({
  kind: "wait",
  approval: row("pending"),
  created: true,
  requestCount: 1,
  notify: true,
  expiresAt: row("pending").expires_at,
});

type Handler = (a: Record<string, unknown>) => Promise<{ content: Array<{ text: string }>; isError?: true }>;

function setup(opts: { read: WaitStatus | null; role?: "owner" | "member" }) {
  const grants = new ExecutionGrants();
  const sendToClient = vi.fn(() => true);
  const onRequested = vi.fn(async () => {});
  const consume = vi.fn(async () => ({ consumed: true as const }));
  const approval = {
    isEnabled: async () => true,
    workspaceId: WORKSPACE_ID,
    grants,
    resolveServerDerived: async (t: string) => SAMPLES[t].server as Record<string, string>,
    submit: async () => waitRequest(),
    readStatus: async () => opts.read,
    consume,
    viewerRole: async () => opts.role ?? "owner",
    onRequested,
    waitOptions: { deadlineMs: 30, sleep: (ms: number) => new Promise<void>((r) => setTimeout(r, Math.min(ms, 5))) },
  } as unknown as ApprovalGateDeps;
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
    deps: {
      abortableReviewGate: vi.fn(() => Promise.resolve("Approve")),
      sendToClient,
      notifyOfflineUser: vi.fn().mockResolvedValue(true),
      updateConversationStatus: vi.fn(async () => {}),
      approval,
      approvalFailClosed: true,
    },
  } as unknown as CanUseToolContext;
  const canUseTool = createCanUseTool(ctx);
  const call = (input: Record<string, unknown>) =>
    canUseTool(PUSH, input, { signal: new AbortController().signal, toolUseID: "t", requestId: "r" } as never) as Promise<{
      behavior: string;
      message?: string;
      updatedInput?: Record<string, unknown>;
    }>;
  // The real builder over the SAME grants object (what cc-dispatcher does through the registrar).
  const pushTool = buildGithubPushBranchTool({
    installationId: 1,
    owner: "example-org",
    repo: "example-repo",
    defaultBranch: "main",
    workspacePath: "/tmp/ws",
    grants,
    requireGrant: true,
  }) as unknown as { handler: Handler };
  return { call, grants, sendToClient, onRequested, consume, handler: pushTool.handler };
}

beforeEach(() => {
  clearAllWaiters();
  vi.clearAllMocks();
  h.pushBranch.mockReset().mockResolvedValue({ branch: INPUT.branch, pushed: true });
  process.env.SENTRY_USERID_PEPPER = "cc-push-gate-flow-test-pepper";
});

const frames = (s: { sendToClient: ReturnType<typeof vi.fn> }, type: string) =>
  s.sendToClient.mock.calls.filter((c) => (c[1] as { type?: string } | undefined)?.type === type).map((c) => c[1] as Record<string, unknown>);

describe("approved: the gate allows, writes a grant carrying the commit, and the handler pushes exactly that commit", () => {
  test("allow -> grant with headSha -> pushBranch(commitSha = approved sha) for the closed-over repo", async () => {
    const s = setup({ read: "approved" });
    const verdict = await s.call({ ...INPUT });
    expect(verdict.behavior).toBe("allow");
    expect(s.consume).toHaveBeenCalledTimes(1);
    expect(s.grants.enforcing).toBe(true);
    expect(s.grants.size()).toBe(1);

    // The SDK would now run the handler with the (possibly updated) input the gate allowed.
    const res = await s.handler({ ...(verdict.updatedInput ?? INPUT) });
    expect(res.isError).toBeUndefined();
    expect(h.pushBranch).toHaveBeenCalledTimes(1);
    expect(h.pushBranch.mock.calls[0][0]).toMatchObject({
      owner: "example-org",
      repo: "example-repo",
      workspacePath: "/tmp/ws",
      branch: INPUT.branch,
      force: false,
      commitSha: SHA,
    });
    // The grant is one-shot.
    expect(s.grants.size()).toBe(0);
    const again = await s.handler({ ...INPUT });
    expect(again.isError).toBe(true);
    expect(h.pushBranch).toHaveBeenCalledTimes(1);
  });

  test("the durable surfaces run for an Owner requester: the approval_request frame names the tool and onRequested fires", async () => {
    const s = setup({ read: "approved", role: "owner" });
    await s.call({ ...INPUT });
    const requests = frames(s, "approval_request");
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ approvalId: APPROVAL_ID, toolName: PUSH, status: "pending", viewerRole: "owner", agentWaiting: true });
    expect(s.onRequested).toHaveBeenCalledTimes(1);
    expect(s.onRequested.mock.calls[0]).toEqual([expect.objectContaining({ approvalId: APPROVAL_ID, created: true, notify: true })]);
  });

  test("a non-Owner requester (viewerRole member) is shown the read-only card, and the push still waits for the Owner", async () => {
    const s = setup({ read: null, role: "member" });
    const verdict = await s.call({ ...INPUT });
    const requests = frames(s, "approval_request");
    expect(requests).toHaveLength(1);
    expect(requests[0]).toMatchObject({ viewerRole: "member", toolName: PUSH });
    expect(verdict).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(s.onRequested).toHaveBeenCalledTimes(1);
    expect(h.pushBranch).not.toHaveBeenCalled();
  });
});

describe("denied or undecided: nothing is pushed, the text is static, and no grant is left behind", () => {
  test("the Owner denies -> the static rejected text, no push, no grant", async () => {
    const s = setup({ read: "rejected" });
    const verdict = await s.call({ ...INPUT });
    expect(verdict).toEqual({ behavior: "deny", message: APPROVAL_REJECTED_DENY });
    expect(h.pushBranch).not.toHaveBeenCalled();
    expect(s.grants.size()).toBe(0);
    expect(s.consume).not.toHaveBeenCalled();
  });

  test("the wait ends undecided -> the static pending text, no push, no grant", async () => {
    const s = setup({ read: null });
    const verdict = await s.call({ ...INPUT });
    expect(verdict).toEqual({ behavior: "deny", message: APPROVAL_PENDING_DENY });
    expect(h.pushBranch).not.toHaveBeenCalled();
    expect(s.grants.size()).toBe(0);
  });

  test.each([
    ["rejected", "rejected" as WaitStatus | null],
    ["undecided", null],
  ])("the %s deny text contains no tool input (no branch name, no commit sha, no repository)", async (_n, read) => {
    const s = setup({ read });
    const verdict = await s.call({ ...INPUT });
    expect(verdict.behavior).toBe("deny");
    const text = verdict.message ?? "";
    expect(text).not.toContain(INPUT.branch);
    expect(text).not.toContain(SHA);
    expect(text).not.toContain("example-org");
    expect(text).not.toContain("example-repo");
  });

  test("the handler called directly after a deny finds no grant: refused as grant_missing, pushBranch not called", async () => {
    const s = setup({ read: "rejected" });
    await s.call({ ...INPUT });
    expect(s.grants.enforcing).toBe(true);
    const res = await s.handler({ ...INPUT });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toMatchObject({ error: GRANT_MISSING_MESSAGE, code: "approval_grant_missing", status: 403 });
    expect(h.pushBranch).not.toHaveBeenCalled();
  });

  test("the handler called with the gate never having run is refused too (requireGrant, not the legacy path)", async () => {
    const s = setup({ read: "approved" });
    expect(s.grants.enforcing).toBe(false);
    const res = await s.handler({ ...INPUT });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text).code).toBe("approval_grant_missing");
    expect(h.pushBranch).not.toHaveBeenCalled();
  });
});
