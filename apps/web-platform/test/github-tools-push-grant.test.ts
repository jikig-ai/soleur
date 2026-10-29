/**
 * #4672 R1: the github_push_branch handler and the execution grant. Enforcing + no grant -> nothing is pushed; a grant ->
 * the approved commit is pinned; not enforcing (flag never on) -> legacy parity (no commitSha).
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn((name: string, description: string, schema: unknown, handler: Function) => ({ name, description, schema, handler })),
}));
const m = vi.hoisted(() => ({ pushBranch: vi.fn() }));
vi.mock("@/server/github-read-tools", () => ({}));
vi.mock("@/server/ci-tools", () => ({}));
vi.mock("@/server/github-app", () => ({}));
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: m.pushBranch }));

import { buildGithubTools } from "@/server/github-tools";
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

beforeEach(() => m.pushBranch.mockReset().mockResolvedValue({ branch: "feat-x", pushed: true }));

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
