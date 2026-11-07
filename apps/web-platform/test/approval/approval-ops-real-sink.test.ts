/**
 * #4672 observability, round 2: the ops added for the execution grants and the hash key reach the REAL Sentry sink
 * (real `reportSilentFallback` / `warnSilentFallback` over a spied Sentry and pino logger, as ops-sink.test.ts does), with
 * their `feature`/`op` tags, their own static message and the structured `extra` an alert and a runbook read.
 *
 *  - `approval-grant-refused` (warn): one test per `extra.reason`, driven through the REAL handlers / `checkGrant`.
 *  - `approval-key-unavailable` (error): driven through the REAL `runApprovalGate` and the REAL reattach.
 *  - the flag read-failure report re-arms after its TTL (no latch).
 *
 * Synthesized data only.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  loggerError: vi.fn(),
  loggerWarn: vi.fn(),
  getRuntimeFlag: vi.fn(),
  createShare: vi.fn(),
  setBash: vi.fn(),
  pushBranch: vi.fn(),
  currentWorkspace: { value: "00000000-0000-4000-8000-000000000001" },
}));
vi.mock("@sentry/nextjs", () => ({ captureException: h.captureException, captureMessage: h.captureMessage }));
vi.mock("@/server/logger", () => {
  const log = { info: vi.fn(), warn: h.loggerWarn, error: h.loggerError, debug: vi.fn() };
  return { default: log, createChildLogger: () => log };
});
vi.mock("@/lib/feature-flags/server", () => ({ getRuntimeFlag: (...a: unknown[]) => h.getRuntimeFlag(...a) }));
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (name: string, description: string, _schema: unknown, handler: Function) => ({ name, description, handler }),
}));
vi.mock("@/server/kb-share", () => ({ createShare: (...a: unknown[]) => h.createShare(...a), listShares: vi.fn(), revokeShare: vi.fn(), previewShare: vi.fn() }));
vi.mock("@/server/workspace-resolver", () => ({ resolveCurrentWorkspaceId: vi.fn(async () => h.currentWorkspace.value) }));
vi.mock("@/server/set-bash-autonomous", () => ({ setBashAutonomous: (...a: unknown[]) => h.setBash(...a) }));
vi.mock("@/server/resolve-bash-autonomous", () => ({ resolveBashAutonomous: vi.fn() }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: vi.fn(async () => ({})) }));
vi.mock("@/server/github-read-tools", () => ({}));
vi.mock("@/server/ci-tools", () => ({}));
vi.mock("@/server/github-app", () => ({}));
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: (...a: unknown[]) => h.pushBranch(...a) }));

import { APPROVAL_OPS, GRANT_REFUSED_REASONS } from "@/server/approval/ops";
import { checkGrant, ExecutionGrants, putGrant } from "@/server/approval/grants";
import { canonicalizeAction, ApprovalCanonicalError } from "@/server/approval/canonical";
import { APPROVAL_UNAVAILABLE_DENY, runApprovalGate } from "@/server/approval/gate-flow";
import { FLAG_READ_FAILURE_REPORT_TTL_MS, isApprovalQueueEnabled, resetFlagReadFailureReport } from "@/server/approval/flag";
import { reemitLiveApprovals } from "@/server/approval/reattach";
import { buildGithubTools } from "@/server/github-tools";
import { buildKbShareTools } from "@/server/kb-share-tools";
import { buildWorkspaceSettingsTools } from "@/server/workspace-settings-tools";
import type { ApprovalGateDeps } from "@/server/approval/gate-types";
import type { ApprovalRpcClient } from "@/server/approval/service";
import { APPROVAL_ID, CONVERSATION_ID, OTHER_WORKSPACE_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const KB = TOOLS.kbShareCreate;
const SET = TOOLS.setAutonomous;
const PUSH = TOOLS.pushBranch;
const SHA = "c".repeat(40);

type Handler = (a: Record<string, unknown>) => Promise<{ content: Array<{ text: string }>; isError?: boolean }>;
const kbHandler = (grants: ExecutionGrants): Handler =>
  (buildKbShareTools({ serviceClient: {} as never, userId: USER_ID, kbRoot: "/k", baseUrl: "https://app.test", grants }) as unknown as Array<{ name: string; handler: Handler }>).find(
    (t) => t.name === "kb_share_create",
  )!.handler;
const setHandler = (grants: ExecutionGrants): Handler =>
  (buildWorkspaceSettingsTools({ userId: USER_ID, grants, resolveWorkspaceId: async () => h.currentWorkspace.value }).tools as unknown as Array<{ name: string; handler: Handler }>).find(
    (t) => t.name === "workspace_set_autonomous",
  )!.handler;
const pushHandler = (grants: ExecutionGrants): Handler =>
  (buildGithubTools({ installationId: 1, owner: "o", repo: "r", defaultBranch: "main", workspacePath: "/w", workflowRateLimiter: {} as never, grants }).tools as unknown as Array<{
    name: string;
    handler: Handler;
  }>).find((t) => t.name === "github_push_branch")!.handler;

const enforcing = () => {
  const g = new ExecutionGrants();
  g.enforcing = true;
  return g;
};

/** The single Sentry event of the op, asserted as the alert/runbook would read it. */
function sentryEvent(key: keyof typeof APPROVAL_OPS) {
  const calls = h.captureMessage.mock.calls.filter((c) => (c[1] as { tags?: { op?: string } }).tags?.op === APPROVAL_OPS[key].op);
  expect(calls, `Sentry events for ${APPROVAL_OPS[key].op}`).toHaveLength(1);
  const [message, ctx] = calls[0] as [string, { level: string; tags: Record<string, string>; extra: Record<string, unknown> }];
  expect(message).toBe(APPROVAL_OPS[key].message);
  expect(ctx.tags).toMatchObject({ feature: "approval-queue", op: APPROVAL_OPS[key].op });
  expect(h.captureException).not.toHaveBeenCalled();
  return ctx;
}

beforeEach(() => {
  vi.clearAllMocks();
  h.currentWorkspace.value = WORKSPACE_ID;
  h.createShare.mockReset().mockResolvedValue({ ok: true, token: "t", url: "/shared/t", documentPath: "a.md", size: 1 });
  h.setBash.mockReset().mockResolvedValue(true);
  h.pushBranch.mockReset().mockResolvedValue({ branch: "feat-x", pushed: true });
  resetFlagReadFailureReport();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("approval-grant-refused: registry", () => {
  it("is a warn op with its own op name and a unique static message; the reasons are a closed set", () => {
    expect(APPROVAL_OPS.grantRefused).toMatchObject({ op: "approval-grant-refused", level: "warn" });
    expect(GRANT_REFUSED_REASONS).toEqual(["grant_missing", "workspace_changed", "commit_mismatch", "commit_unavailable", "grant_error"]);
    const others: Array<{ op: string; message: string }> = Object.values(APPROVAL_OPS).filter((o) => o.op !== "approval-grant-refused");
    expect(others.some((o) => o.message === APPROVAL_OPS.grantRefused.message)).toBe(false);
  });
});

describe("approval-grant-refused: one event per reason, through the real handlers", () => {
  it("grant_missing: an enforcing session, no grant (push, kb_share, settings all report it with their own tool)", async () => {
    for (const [tool, run] of [
      [PUSH, () => pushHandler(enforcing())({ branch: "feat-x", force: false })],
      [KB, () => kbHandler(enforcing())({ documentPath: "a.md" })],
      [SET, () => setHandler(enforcing())({ value: true })],
    ] as const) {
      vi.clearAllMocks();
      const res = await run();
      expect(res.isError, tool).toBe(true);
      const ctx = sentryEvent("grantRefused");
      expect(ctx.level).toBe("warning");
      expect(ctx.extra).toMatchObject({ reason: "grant_missing", tool });
    }
    expect(h.pushBranch).not.toHaveBeenCalled();
    expect(h.createShare).not.toHaveBeenCalled();
    expect(h.setBash).not.toHaveBeenCalled();
  });

  it("grant_error: args that cannot be keyed are reported as grant_error with the error CODE, never its message", async () => {
    const g = enforcing();
    expect(checkGrant(g, PUSH, { branch: "" })).toEqual({ kind: "refuse" });
    const ctx = sentryEvent("grantRefused");
    expect(ctx.extra).toMatchObject({ reason: "grant_error", tool: PUSH, code: "invalid_input", errName: "ApprovalCanonicalError" });
  });

  it("workspace_changed: approved in W1, active workspace W2 (kb_share and settings)", async () => {
    for (const [tool, mk, args] of [
      [KB, kbHandler, { documentPath: "a.md" }],
      [SET, setHandler, { value: true }],
    ] as const) {
      vi.clearAllMocks();
      h.currentWorkspace.value = WORKSPACE_ID;
      const g = enforcing();
      putGrant(g, tool, args, { workspaceId: WORKSPACE_ID });
      h.currentWorkspace.value = OTHER_WORKSPACE_ID;
      const res = await mk(g)({ ...args });
      expect(res.isError, tool).toBe(true);
      expect(JSON.parse(res.content[0].text)).toMatchObject({ code: "workspace_changed", status: 409 });
      const ctx = sentryEvent("grantRefused");
      expect(ctx.extra).toMatchObject({ reason: "workspace_changed", tool });
    }
  });

  it("commit_mismatch: a push grant that carries no headSha refuses (never pushes HEAD)", async () => {
    const g = enforcing();
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WORKSPACE_ID });
    const res = await pushHandler(g)({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(h.pushBranch).not.toHaveBeenCalled();
    expect(sentryEvent("grantRefused").extra).toMatchObject({ reason: "commit_mismatch", tool: PUSH });
  });

  it("commit_unavailable: the approved commit cannot be pushed", async () => {
    const g = enforcing();
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WORKSPACE_ID, headSha: SHA });
    const err = new Error("Approved commit is not present in the workspace repository");
    err.name = "ApprovedCommitUnavailableError";
    h.pushBranch.mockRejectedValueOnce(err);
    const res = await pushHandler(g)({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(sentryEvent("grantRefused").extra).toMatchObject({ reason: "commit_unavailable", tool: PUSH });
  });

  it("a granted, matching call and a legacy (never enforcing) call report nothing", async () => {
    const g = enforcing();
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WORKSPACE_ID, headSha: SHA });
    await pushHandler(g)({ branch: "feat-x", force: false });
    await kbHandler(new ExecutionGrants())({ documentPath: "a.md" });
    expect(h.captureMessage).not.toHaveBeenCalled();
  });

  it("one shape across the three tools: JSON {error, code, status} with a terminal text (not performed, no retry in this conversation)", async () => {
    const bodies = [
      JSON.parse((await pushHandler(enforcing())({ branch: "feat-x", force: false })).content[0].text),
      JSON.parse((await kbHandler(enforcing())({ documentPath: "a.md" })).content[0].text),
      JSON.parse((await setHandler(enforcing())({ value: true })).content[0].text),
    ];
    for (const b of bodies) {
      expect(Object.keys(b).sort()).toEqual(["code", "error", "status"]);
      expect(b.error).toMatch(/NOT performed/);
      expect(b.error).toMatch(/Do not retry in this conversation/);
    }
    expect(new Set(bodies.map((b) => JSON.stringify(b))).size).toBe(1);
  });
});

describe("approval-key-unavailable: an unset SENTRY_USERID_PEPPER", () => {
  const saved = process.env.SENTRY_USERID_PEPPER;
  afterEach(() => {
    if (saved === undefined) delete process.env.SENTRY_USERID_PEPPER;
    else process.env.SENTRY_USERID_PEPPER = saved;
  });

  it("is an ERROR-level op with its own message", () => {
    expect(APPROVAL_OPS.keyUnavailable).toMatchObject({ op: "approval-key-unavailable", level: "error" });
  });

  it("the gate denies with the unavailable text and reaches Sentry as its own error event (literal-null path, code in extra)", async () => {
    delete process.env.SENTRY_USERID_PEPPER;
    const grants = new ExecutionGrants();
    const submit = vi.fn();
    const approval: ApprovalGateDeps = {
      isEnabled: async () => true,
      workspaceId: WORKSPACE_ID,
      grants,
      resolveServerDerived: async () => undefined,
      submit,
      readStatus: vi.fn(),
      consume: vi.fn(),
      viewerRole: async () => "owner",
    };
    const res = await runApprovalGate({
      toolName: TOOLS.emailSend,
      toolInput: structuredClone(SAMPLES[TOOLS.emailSend].input),
      callSignal: undefined,
      controllerSignal: new AbortController().signal,
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      approval,
      sendToClient: () => true,
      hold: async (_i, _s, wait) => wait(),
      allow: (i) => ({ behavior: "allow", updatedInput: i }),
      logDecision: () => {},
    });
    expect(res).toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY });
    expect(submit).not.toHaveBeenCalled();
    const ctx = sentryEvent("keyUnavailable");
    expect(ctx.level).toBe("error");
    expect(ctx.extra).toMatchObject({ code: "key_unavailable", tool: TOOLS.emailSend, conversationId: CONVERSATION_ID });
    // Not folded into the generic gate-failure group.
    expect(h.captureMessage.mock.calls.some((c) => (c[1] as { tags?: { op?: string } }).tags?.op === "approval-gate-failed")).toBe(false);
    // The pino mirror line carries the tags and no error object (nothing for the pino integration to capture).
    const [fields] = h.loggerError.mock.calls[0] as [Record<string, unknown>];
    expect(fields).toMatchObject({ feature: "approval-queue", op: "approval-key-unavailable" });
    expect(fields.err).toBeNull();
  });

  it("the hash key error is the canonical key_unavailable code", () => {
    expect(new ApprovalCanonicalError("key_unavailable").code).toBe("key_unavailable");
    expect(() => canonicalizeAction(TOOLS.emailSend, SAMPLES[TOOLS.emailSend].input)).not.toThrow();
  });

  it("reattach reports the same op, tagged with the approval id, and shows no card", async () => {
    process.env.SENTRY_USERID_PEPPER = "reattach-test-pepper";
    const sample = SAMPLES[TOOLS.emailSend];
    const action = canonicalizeAction(TOOLS.emailSend, sample.input, sample.server);
    const row = {
      id: APPROVAL_ID,
      workspace_id: WORKSPACE_ID,
      conversation_id: CONVERSATION_ID,
      requested_by_user_id: USER_ID,
      tool_name: TOOLS.emailSend,
      action_sha256: "a".repeat(64),
      status: "pending",
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
      created_at: new Date().toISOString(),
      canonical_action: action,
    };
    const client: ApprovalRpcClient = { rpc: async () => ({ data: [{ approval: row, request_count: 1 }], error: null }) };
    const send = vi.fn(() => true);
    delete process.env.SENTRY_USERID_PEPPER;
    const sent = await reemitLiveApprovals({
      userId: USER_ID,
      conversationId: CONVERSATION_ID,
      workspaceId: WORKSPACE_ID,
      send,
      client: () => client,
      viewerRole: async () => "owner",
      isEnabled: async () => true,
    });
    expect(sent).toBe(0);
    expect(send).not.toHaveBeenCalled();
    const calls = h.captureMessage.mock.calls.filter((c) => (c[1] as { tags?: { op?: string } }).tags?.op === "approval-key-unavailable");
    expect(calls).toHaveLength(1);
    expect((calls[0][1] as { tags: Record<string, string> }).tags).toMatchObject({ approval_id: APPROVAL_ID });
    expect((calls[0][1] as { extra: Record<string, unknown> }).extra).toMatchObject({ code: "key_unavailable", stage: "reattach" });
    expect(h.captureMessage.mock.calls.some((c) => (c[1] as { tags?: { op?: string } }).tags?.op === "approval-reattach-failed")).toBe(false);
  });
});

describe("approval-flag-read-failed: the report re-arms after its TTL instead of latching", () => {
  it("reports once per window, stays quiet inside it, and reports again after the TTL", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-29T10:00:00Z"));
    h.getRuntimeFlag.mockRejectedValue(new Error("flagsmith down"));
    const read = () => isApprovalQueueEnabled({ userId: USER_ID, workspaceId: WORKSPACE_ID });
    const events = () => h.captureMessage.mock.calls.filter((c) => (c[1] as { tags?: { op?: string } }).tags?.op === "approval-flag-read-failed").length;

    await expect(read()).resolves.toBe(false);
    await expect(read()).resolves.toBe(false);
    expect(events()).toBe(1);

    vi.setSystemTime(Date.now() + FLAG_READ_FAILURE_REPORT_TTL_MS - 1_000);
    await read();
    expect(events()).toBe(1);

    vi.setSystemTime(Date.now() + 2_000);
    await expect(read()).resolves.toBe(false);
    expect(events()).toBe(2);
    expect(FLAG_READ_FAILURE_REPORT_TTL_MS).toBe(10 * 60 * 1000);
  });
});
