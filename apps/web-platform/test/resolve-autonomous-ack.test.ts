import { describe, it, expect, vi, beforeEach } from "vitest";

// feat-bash-autonomous-default-on — resolveAutonomousAck reads
// workspaces.autonomous_disclosure_ack_at ONLY via the membership-checked
// get_workspace_autonomous_ack RPC. It is FAIL-CLOSED to `null` (= not-acked =
// HOLD), the OPPOSITE boolean direction from resolveBashAutonomous's `?? false`
// — a read failure must NEVER silently treat the workspace as acked (which
// would let the first auto-run proceed without the disclosure).

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

describe("resolveAutonomousAck (workspace-scoped, RPC-only, fail-closed null)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns the timestamp when the RPC returns one for the active workspace", async () => {
    const ts = "2026-06-04T12:00:00.000Z";
    mockRpc.mockResolvedValue({ data: ts, error: null });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    const result = await resolveAutonomousAck("user-1", "ws-active");
    expect(result).toBe(ts);
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_autonomous_ack", {
      p_workspace_id: "ws-active",
    });
  });

  it("returns null when the RPC returns null (not yet acked)", async () => {
    mockRpc.mockResolvedValue({ data: null, error: null });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    expect(await resolveAutonomousAck("user-1", "ws-1")).toBeNull();
  });

  it("undefined workspace defaults to the solo workspace (= userId)", async () => {
    mockRpc.mockResolvedValue({ data: null, error: null });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    await resolveAutonomousAck("user-solo");
    expect(mockRpc).toHaveBeenCalledWith("get_workspace_autonomous_ack", {
      p_workspace_id: "user-solo",
    });
  });

  it("FAIL-CLOSED: RPC error → null AND mirrors to Sentry", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    expect(await resolveAutonomousAck("user-1", "ws-1")).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "resolve-autonomous-ack" }),
    );
  });

  it("FAIL-CLOSED: RuntimeAuthError → null AND mirrors", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback } = await import("@/server/observability");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("jwt_mint", "token expired");
    });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    expect(await resolveAutonomousAck("user-1", "ws-1")).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({ feature: "resolve-autonomous-ack" }),
    );
  });

  it("re-throws non-RuntimeAuthError errors (not swallowed as null)", async () => {
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new Error("unexpected failure");
    });
    const { resolveAutonomousAck } = await import(
      "@/server/resolve-autonomous-ack"
    );
    await expect(resolveAutonomousAck("user-1", "ws-1")).rejects.toThrow(
      "unexpected failure",
    );
  });
});
