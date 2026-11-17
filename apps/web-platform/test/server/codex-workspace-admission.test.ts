import { describe, expect, it, vi } from "vitest";
import { verifyCodexWorkspace } from "@/server/codex-workspace-admission";

describe("Codex workspace admission observation", () => {
  const setup = () => ({
    conversationWorkspaceId: "workspace-a", bindingWorkspaceId: "workspace-a", conversationRepoUrl: "repo-a",
    readWorkspace: vi.fn().mockResolvedValue("workspace-a"),
    readRepo: vi.fn().mockResolvedValue({url:"repo-a", degraded:false}), assertCurrent: vi.fn(),
  });
  it("requires the same non-null workspace before and after a healthy matching repo read", async () => {
    const input=setup(); await expect(verifyCodexWorkspace(input)).resolves.toBeUndefined();
    expect(input.readWorkspace).toHaveBeenCalledTimes(2); expect(input.readRepo).toHaveBeenCalledWith("workspace-a");
  });
  it("rejects a sibling workspace even when its repository is identical", async () => {
    const input=setup(); input.readWorkspace.mockResolvedValue("workspace-b");
    await expect(verifyCodexWorkspace(input)).rejects.toThrow(); expect(input.readRepo).not.toHaveBeenCalled();
  });
  it("rejects a mismatched engine binding", async () => {
    const input=setup(); input.bindingWorkspaceId="workspace-b";
    await expect(verifyCodexWorkspace(input)).rejects.toThrow(); expect(input.readRepo).not.toHaveBeenCalled();
  });
  it.each([null, "workspace-b"])("rejects a missing or switched workspace: %s", async (workspace) => {
    const input=setup(); input.readWorkspace.mockResolvedValueOnce("workspace-a").mockResolvedValueOnce(workspace);
    await expect(verifyCodexWorkspace(input)).rejects.toThrow();
  });
  it("rejects failed workspace reads and degraded or empty repository evidence", async () => {
    for (const result of [{url:null,degraded:true},{url:"repo-a",degraded:true},{url:null,degraded:false},{url:"repo-b",degraded:false}]) {
      const input=setup(); input.readRepo.mockResolvedValue(result); await expect(verifyCodexWorkspace(input)).rejects.toThrow();
    }
    const input=setup(); input.readWorkspace.mockRejectedValue(new Error("synthetic")); await expect(verifyCodexWorkspace(input)).rejects.toThrow();
    const late=setup(); late.readWorkspace.mockResolvedValueOnce("workspace-a").mockRejectedValueOnce(new Error("synthetic"));
    await expect(verifyCodexWorkspace(late)).rejects.toThrow();
  });
  it.each([1,2,3])("propagates session replacement after awaited read %i", async (call) => {
    const input=setup(); let calls=0; input.assertCurrent.mockImplementation(()=>{ if (++calls===call) throw new Error("replaced"); });
    await expect(verifyCodexWorkspace(input)).rejects.toThrow("replaced");
    if (call===1) expect(input.readRepo).not.toHaveBeenCalled();
  });
});
