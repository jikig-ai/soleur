/**
 * #4672 R1: the github_push_branch handler and the execution grant. Enforcing + no grant -> nothing is pushed; a grant ->
 * the approved commit is pinned; not enforcing (flag never on) -> legacy parity (no commitSha).
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn((name: string, description: string, schema: unknown, handler: Function) => ({ name, description, schema, handler })),
}));
const m = vi.hoisted(() => ({ pushBranch: vi.fn(), reportGrantRefused: vi.fn() }));
// Pass-through wrapper: the real grants module with ONE observable seam on the refusal report (the report is a side effect
// of the handler's own refusal path; the `checkGrant` report inside grants.ts calls the local binding, not this wrapper).
vi.mock("@/server/approval/grants", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/approval/grants")>();
  return {
    ...actual,
    reportGrantRefused: (...args: Parameters<typeof actual.reportGrantRefused>) => {
      m.reportGrantRefused(...args);
      return actual.reportGrantRefused(...args);
    },
  };
});
vi.mock("@/server/github-read-tools", () => ({}));
vi.mock("@/server/ci-tools", () => ({}));
vi.mock("@/server/github-app", () => ({}));
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: m.pushBranch }));

import { buildGithubPushBranchTool, buildGithubTools, GITHUB_PUSH_BRANCH_TOOL_FQN, PUSH_FAILED_APPROVAL_SPENT } from "@/server/github-tools";
import { ExecutionGrants, GRANT_MISSING_MESSAGE, putGrant } from "@/server/approval/grants";

const PUSH = "mcp__soleur_platform__github_push_branch";
const SHA = "c".repeat(40);
const WS = "00000000-0000-4000-8000-000000000001";

type ToolStub = { name: string; handler: (a: Record<string, unknown>) => Promise<{ content: Array<{ text: string }>; isError?: true }> };

function pushTool(grants: ExecutionGrants): ToolStub {
  const { tools } = buildGithubTools({
    installationId: 1,
    owner: "o",
    repo: "r",
    defaultBranch: "main",
    workspacePath: "/w",
    workflowRateLimiter: {} as never,
    grants,
  });
  return tools.find((t) => (t as unknown as ToolStub).name === "github_push_branch") as unknown as ToolStub;
}

beforeEach(() => {
  m.pushBranch.mockReset().mockResolvedValue({ branch: "feat-x", pushed: true });
  m.reportGrantRefused.mockReset();
});

describe("github_push_branch + execution grant", () => {
  it("enforcing and no grant: refuses with the grant-missing text and pushes nothing", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    const res = await pushTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    // The one refusal shape across the three grant-checked tools: JSON {error, code, status}, error = terminal text.
    expect(JSON.parse(res.content[0].text)).toEqual({ error: GRANT_MISSING_MESSAGE, code: "approval_grant_missing", status: 403 });
    expect(GRANT_MISSING_MESSAGE).toMatch(/Do not retry in this conversation/);
    expect(GRANT_MISSING_MESSAGE).toMatch(/NOT performed/);
    expect(m.pushBranch).not.toHaveBeenCalled();
  });

  it("a grant pins the approved commit: pushBranch gets commitSha = the approved headSha", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    const res = await pushTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBeUndefined();
    expect(m.pushBranch).toHaveBeenCalledTimes(1);
    expect(m.pushBranch.mock.calls[0][0]).toMatchObject({ branch: "feat-x", commitSha: SHA });
  });

  it("the grant is one-shot: a second identical call is refused", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    const t = pushTool(g);
    await t.handler({ branch: "feat-x", force: false });
    const second = await t.handler({ branch: "feat-x", force: false });
    expect(second.isError).toBe(true);
    expect(m.pushBranch).toHaveBeenCalledTimes(1);
  });

  it("a grant for another branch does not release this push", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-other" }, { workspaceId: WS, headSha: SHA });
    const res = await pushTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(m.pushBranch).not.toHaveBeenCalled();
  });

  it("a grant that carries no headSha REFUSES (never pushes HEAD) and is reported as commit_mismatch", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS });
    const res = await pushTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text).code).toBe("approved_commit_unavailable");
    expect(m.pushBranch).not.toHaveBeenCalled();
  });

  it("the approved commit is gone from the workspace: terminal refusal, not a generic push error", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    const err = new Error("Approved commit is not present in the workspace repository");
    err.name = "ApprovedCommitUnavailableError";
    m.pushBranch.mockRejectedValueOnce(err);
    const res = await pushTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toMatchObject({ code: "approved_commit_unavailable", status: 409 });
  });

  it("not enforcing (the flag never turned on): legacy parity, commitSha undefined", async () => {
    await pushTool(new ExecutionGrants()).handler({ branch: "feat-x", force: false });
    await pushTool(new ExecutionGrants()).handler({ branch: "feat-x", force: false });
    expect(m.pushBranch).toHaveBeenCalledTimes(2);
    for (const c of m.pushBranch.mock.calls) expect(c[0].commitSha).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------------------------------------------------
// #11636: the exported push builder the cc dispatcher registers behind the approval gate. `requireGrant: true` makes the
// handler refuse unless a gate-written grant exists, even when the sticky `enforcing` bit never turned on.
// ---------------------------------------------------------------------------------------------------------------------
type SchemaStub = ToolStub & { schema: Record<string, unknown> };

function strictTool(grants: ExecutionGrants, requireGrant = true): SchemaStub {
  const t = buildGithubPushBranchTool({
    installationId: 7,
    owner: "closed-owner",
    repo: "closed-repo",
    defaultBranch: "develop",
    workspacePath: "/closed/ws",
    grants,
    requireGrant,
  });
  return t as unknown as SchemaStub;
}

describe("buildGithubPushBranchTool (requireGrant: true, the cc registration)", () => {
  it("exports the fully-qualified tool name the gate and the allow list key on", () => {
    expect(GITHUB_PUSH_BRANCH_TOOL_FQN).toBe(PUSH);
  });

  it("enforcing false + no grant => refused as grant_missing, reported, and pushBranch is NOT called", async () => {
    const g = new ExecutionGrants();
    expect(g.enforcing).toBe(false);
    const res = await strictTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toEqual({ error: GRANT_MISSING_MESSAGE, code: "approval_grant_missing", status: 403 });
    expect(m.pushBranch).not.toHaveBeenCalled();
    expect(m.reportGrantRefused).toHaveBeenCalledWith(PUSH, "grant_missing");
  });

  it("legacy parity: the SAME state through buildGithubTools (requireGrant false) still pushes HEAD, and reports nothing", async () => {
    const res = await pushTool(new ExecutionGrants()).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBeUndefined();
    expect(m.pushBranch).toHaveBeenCalledTimes(1);
    expect(m.pushBranch.mock.calls[0][0].commitSha).toBeUndefined();
    expect(m.reportGrantRefused).not.toHaveBeenCalled();
    // And the builder itself with requireGrant false is the legacy handler.
    await strictTool(new ExecutionGrants(), false).handler({ branch: "feat-x", force: false });
    expect(m.pushBranch).toHaveBeenCalledTimes(2);
  });

  it("a gate-written grant with a valid commit pushes exactly the approved commit with the CLOSED-OVER values", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    const res = await strictTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBeUndefined();
    // With a grant the result names the commit that landed (the approved one), so the model can report it.
    expect(JSON.parse(res.content[0].text)).toEqual({ branch: "feat-x", pushed: true, commit: SHA });
    expect(m.pushBranch).toHaveBeenCalledTimes(1);
    expect(m.pushBranch.mock.calls[0][0]).toEqual({
      installationId: 7,
      owner: "closed-owner",
      repo: "closed-repo",
      workspacePath: "/closed/ws",
      branch: "feat-x",
      force: false,
      defaultBranch: "develop",
      commitSha: SHA,
      hardened: true,
    });
    expect(m.reportGrantRefused).not.toHaveBeenCalled();
  });

  it("the legacy shape is unchanged: no grant => the success JSON has no commit key, and a push failure carries no approval-spent line", async () => {
    const ok = await pushTool(new ExecutionGrants()).handler({ branch: "feat-x", force: false });
    expect(JSON.parse(ok.content[0].text)).toEqual({ branch: "feat-x", pushed: true });
    const legacy = strictTool(new ExecutionGrants(), false);
    m.pushBranch.mockRejectedValueOnce(new Error("non-fast-forward"));
    const failed = await legacy.handler({ branch: "feat-x", force: false });
    expect(failed.content[0].text).toBe("Error pushing branch: non-fast-forward");
  });

  it("the approval-spent line is static: it names no input, branch, path or git output", () => {
    expect(PUSH_FAILED_APPROVAL_SPENT).toMatch(/^The Owner's approval for this push is spent\. A retry needs a new Owner approval/);
    expect(PUSH_FAILED_APPROVAL_SPENT).not.toMatch(/feat-x|\/|git /);
  });

  it("the approval-spent line never claims 'nothing was pushed': a timeout or killed child can fail a push the remote already accepted", () => {
    expect(PUSH_FAILED_APPROVAL_SPENT).toMatch(/may not have been pushed/);
    expect(PUSH_FAILED_APPROVAL_SPENT).toMatch(/may not have landed/);
    expect(PUSH_FAILED_APPROVAL_SPENT).not.toMatch(/nothing was pushed/i);
  });

  it("hardened push is cc-only: the strict builder sets it, buildGithubTools and requireGrant false leave the key ABSENT", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    await strictTool(g).handler({ branch: "feat-x", force: false });
    expect(m.pushBranch.mock.calls[0][0].hardened).toBe(true);
    await pushTool(new ExecutionGrants()).handler({ branch: "feat-x", force: false });
    await strictTool(new ExecutionGrants(), false).handler({ branch: "feat-x", force: false });
    for (const c of m.pushBranch.mock.calls.slice(1)) expect("hardened" in c[0]).toBe(false);
  });

  it("the handler never reads a model-supplied owner/repo/workspacePath/installationId, and the schema is exactly {branch, force}", async () => {
    const t = strictTool(new ExecutionGrants(), false);
    expect(Object.keys(t.schema).sort()).toEqual(["branch", "force"]);
    await t.handler({ branch: "feat-x", force: false, owner: "evil", repo: "evil", workspacePath: "/evil", installationId: 999, defaultBranch: "x" });
    const call = m.pushBranch.mock.calls[0][0];
    expect(call).toMatchObject({ owner: "closed-owner", repo: "closed-repo", workspacePath: "/closed/ws", installationId: 7, defaultBranch: "develop" });
  });

  it("a grant that carries no headSha => commit_mismatch (reported), never a HEAD push", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS });
    const res = await strictTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text).code).toBe("approved_commit_unavailable");
    expect(m.pushBranch).not.toHaveBeenCalled();
    expect(m.reportGrantRefused).toHaveBeenCalledWith(PUSH, "commit_mismatch");
  });

  it("the approved commit is gone from the workspace => commit_unavailable (reported)", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    const err = new Error("Approved commit is not present in the workspace repository");
    err.name = "ApprovedCommitUnavailableError";
    m.pushBranch.mockRejectedValueOnce(err);
    const res = await strictTool(g).handler({ branch: "feat-x", force: false });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text)).toMatchObject({ code: "approved_commit_unavailable", status: 409 });
    expect(m.reportGrantRefused).toHaveBeenCalledWith(PUSH, "commit_unavailable");
  });

  it("pushBranch failing AFTER the grant was taken: isError 'Error pushing branch: ...', the grant is spent, a retry is refused as grant_missing", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, PUSH, { branch: "feat-x" }, { workspaceId: WS, headSha: SHA });
    m.pushBranch.mockRejectedValueOnce(new Error("non-fast-forward"));
    const t = strictTool(g);
    const first = await t.handler({ branch: "feat-x", force: false });
    expect(first.isError).toBe(true);
    // The strict path says the approval is spent (a blind retry would open a fresh Owner approval for nothing).
    expect(first.content[0].text).toBe(`Error pushing branch: non-fast-forward\n${PUSH_FAILED_APPROVAL_SPENT}`);
    const second = await t.handler({ branch: "feat-x", force: false });
    expect(second.isError).toBe(true);
    expect(JSON.parse(second.content[0].text).code).toBe("approval_grant_missing");
    expect(m.pushBranch).toHaveBeenCalledTimes(1);
  });
});
