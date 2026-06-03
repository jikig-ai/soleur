import { describe, it, expect, vi, beforeEach } from "vitest";

// Issue B part 2 (AC15) — resolveBashAutonomous reads workspaces.bash_autonomous
// ONLY via the membership-checked get_workspace_bash_autonomous RPC, and is
// FAIL-CLOSED: any error / null / RuntimeAuthError resolves false so a
// settings-read failure can never silently enable the approval-bypass.

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

describe("resolveBashAutonomous (workspace-scoped, RPC-only, fail-closed)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns true when the RPC returns true for the active workspace", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    const result = await resolveBashAutonomous("user-1", "ws-active");
    expect(result).toBe(true);
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_bash_autonomous", {
      p_workspace_id: "ws-active",
    });
  });

  it("returns false when the RPC returns false", async () => {
    mockRpc.mockResolvedValue({ data: false, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
  });

  it("undefined claim defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: true, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    await resolveBashAutonomous("user-solo");
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_bash_autonomous", {
      p_workspace_id: "user-solo",
    });
  });

  it("FAIL-CLOSED: RPC null (non-member deny path) → false", async () => {
    mockRpc.mockResolvedValue({ data: null, error: null });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-not-mine")).toBe(false);
  });

  it("FAIL-CLOSED: RPC error → false AND mirrors to Sentry", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "resolve-bash-autonomous" }),
    );
  });

  it("FAIL-CLOSED: RuntimeAuthError → false AND mirrors", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback } = await import("@/server/observability");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("jwt_mint", "token expired");
    });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    expect(await resolveBashAutonomous("user-1", "ws-1")).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({ feature: "resolve-bash-autonomous" }),
    );
  });

  it("re-throws non-RuntimeAuthError errors (not swallowed as false)", async () => {
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new Error("unexpected failure");
    });
    const { resolveBashAutonomous } = await import(
      "@/server/resolve-bash-autonomous"
    );
    await expect(resolveBashAutonomous("user-1", "ws-1")).rejects.toThrow(
      "unexpected failure",
    );
  });
});
