/**
 * #4672 R1 (ADR-307, execution grants): the two handlers that re-resolve the active workspace at execution
 * (`workspace_set_autonomous`, `kb_share_create`) verify the workspace the Owner approved the action for, and refuse
 * with `workspace_changed` when it moved. No grant while the approval flow is on for the session = refuse.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (name: string, description: string, _schema: unknown, handler: Function) => ({ name, description, handler }),
}));
const m = vi.hoisted(() => ({
  createShare: vi.fn(),
  setBash: vi.fn(),
  currentWorkspace: { value: "ws-approved" },
}));
vi.mock("@/server/kb-share", () => ({
  createShare: m.createShare,
  listShares: vi.fn(),
  revokeShare: vi.fn(),
  previewShare: vi.fn(),
}));
vi.mock("@/server/workspace-resolver", () => ({ resolveCurrentWorkspaceId: vi.fn(async () => m.currentWorkspace.value) }));
vi.mock("@/server/set-bash-autonomous", () => ({ setBashAutonomous: m.setBash }));
vi.mock("@/server/resolve-bash-autonomous", () => ({ resolveBashAutonomous: vi.fn() }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: vi.fn(async () => ({})) }));

import { buildKbShareTools } from "@/server/kb-share-tools";
import { buildWorkspaceSettingsTools } from "@/server/workspace-settings-tools";
import { ExecutionGrants, putGrant } from "@/server/approval/grants";

type Handler = (a: Record<string, unknown>) => Promise<{ content: Array<{ text: string }>; isError?: boolean }>;
const KB = "mcp__soleur_platform__kb_share_create";
const SET = "mcp__soleur_platform__workspace_set_autonomous";

const kbCreate = (grants: ExecutionGrants): Handler =>
  (buildKbShareTools({ serviceClient: {} as never, userId: "u1", kbRoot: "/k", baseUrl: "https://app.test", grants }) as unknown as Array<{
    name: string;
    handler: Handler;
  }>).find((t) => t.name === "kb_share_create")!.handler;

const setAuto = (grants: ExecutionGrants): Handler =>
  (buildWorkspaceSettingsTools({ userId: "u1", grants, resolveWorkspaceId: async () => m.currentWorkspace.value }).tools as unknown as Array<{
    name: string;
    handler: Handler;
  }>).find((t) => t.name === "workspace_set_autonomous")!.handler;

const body = (r: { content: Array<{ text: string }> }) => JSON.parse(r.content[0].text) as Record<string, unknown>;

beforeEach(() => {
  m.createShare.mockReset().mockResolvedValue({ ok: true, token: "t", url: "/shared/t", documentPath: "a.md", size: 1 });
  m.setBash.mockReset().mockResolvedValue(true);
  m.currentWorkspace.value = "ws-approved";
});

describe("kb_share_create", () => {
  const args = { documentPath: "a.md" };
  const granted = () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, KB, args, { workspaceId: "ws-approved" });
    return g;
  };

  it("grant + same workspace: creates the link", async () => {
    const r = await kbCreate(granted())(args);
    expect(r.isError).toBeUndefined();
    expect(m.createShare).toHaveBeenCalledTimes(1);
    expect(m.createShare.mock.calls[0][2]).toBe("ws-approved");
  });

  it("the active workspace changed after approval: refused with workspace_changed, createShare never called", async () => {
    m.currentWorkspace.value = "ws-other";
    const r = await kbCreate(granted())(args);
    expect(r.isError).toBe(true);
    expect(body(r).code).toBe("workspace_changed");
    expect(m.createShare).not.toHaveBeenCalled();
  });

  it("enforcing and no grant: refused, createShare never called", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    const r = await kbCreate(g)(args);
    expect(r.isError).toBe(true);
    expect(body(r).code).toBe("approval_grant_missing");
    expect(m.createShare).not.toHaveBeenCalled();
  });

  it("one-shot: the second identical call is refused", async () => {
    const g = granted();
    const h = kbCreate(g);
    await h(args);
    expect((await h(args)).isError).toBe(true);
    expect(m.createShare).toHaveBeenCalledTimes(1);
  });

  it("not enforcing: legacy behaviour, whatever the workspace", async () => {
    m.currentWorkspace.value = "ws-any";
    expect((await kbCreate(new ExecutionGrants())(args)).isError).toBeUndefined();
    expect((await kbCreate(new ExecutionGrants())(args)).isError).toBeUndefined();
    expect(m.createShare).toHaveBeenCalledTimes(2);
  });
});

describe("workspace_set_autonomous", () => {
  const args = { value: true };
  const granted = () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, SET, args, { workspaceId: "ws-approved" });
    return g;
  };

  it("grant + same workspace: sets it, pinned to the approved workspace", async () => {
    const r = await setAuto(granted())(args);
    expect(r.isError).toBeUndefined();
    expect(m.setBash).toHaveBeenCalledWith("u1", true, "ws-approved");
  });

  it("approved on W1 but the active workspace is W2: refused with workspace_changed, setBashAutonomous never called", async () => {
    m.currentWorkspace.value = "ws-w2";
    const r = await setAuto(granted())(args);
    expect(r.isError).toBe(true);
    expect(body(r).code).toBe("workspace_changed");
    expect(m.setBash).not.toHaveBeenCalled();
  });

  it("enforcing and no grant: refused", async () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    const r = await setAuto(g)(args);
    expect(r.isError).toBe(true);
    expect(body(r).code).toBe("approval_grant_missing");
    expect(m.setBash).not.toHaveBeenCalled();
  });

  it("a grant for value=true does not release value=false", async () => {
    const r = await setAuto(granted())({ value: false });
    expect(r.isError).toBe(true);
    expect(m.setBash).not.toHaveBeenCalled();
  });

  it("not enforcing: legacy call shape (userId, value), no workspace argument", async () => {
    await setAuto(new ExecutionGrants())(args);
    expect(m.setBash).toHaveBeenCalledWith("u1", true);
  });
});
