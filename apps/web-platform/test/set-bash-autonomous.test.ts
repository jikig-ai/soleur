import { describe, it, expect, vi, beforeEach } from "vitest";

// Issue B part 2 (AC15) — setBashAutonomous writes ONLY via the owner-only
// set_workspace_bash_autonomous RPC. On error (owner-deny raise or fault) it
// mirrors to Sentry and RE-THROWS (a write must not silently swallow).

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: mockRpc })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: vi.fn(async (userId: string) => userId),
}));

describe("setBashAutonomous (owner-only RPC write)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("writes true via the RPC for the active workspace and returns the value", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { setBashAutonomous } = await import("@/server/set-bash-autonomous");
    const result = await setBashAutonomous("user-1", true, "ws-active");
    expect(result).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith("set_workspace_bash_autonomous", {
      p_workspace_id: "ws-active",
      p_value: true,
    });
  });

  it("undefined claim defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { setBashAutonomous } = await import("@/server/set-bash-autonomous");
    await setBashAutonomous("user-solo", false);
    expect(mockRpc).toHaveBeenCalledWith("set_workspace_bash_autonomous", {
      p_workspace_id: "user-solo",
      p_value: false,
    });
  });

  it("mirrors to Sentry AND throws on RPC error (owner-deny raise / fault)", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "not authorized: only a workspace owner may set bash_autonomous" },
    });
    const { setBashAutonomous } = await import("@/server/set-bash-autonomous");
    await expect(setBashAutonomous("user-1", true, "ws-1")).rejects.toThrow(
      /failed to set bash_autonomous/i,
    );
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "set-bash-autonomous" }),
    );
  });
});
