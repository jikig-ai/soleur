import { describe, it, expect, vi, beforeEach } from "vitest";

// AC4 — resolveInstallationId reads the workspace credential ONLY via the
// membership-checked resolve_workspace_installation_id SECURITY DEFINER
// RPC (ADR-044). The `.ilike("repo_url", …)` LIKE-injection fallback and
// the unscoped `workspace_members … LIMIT 1` sibling lookup are DELETED.
//
//   (a) a member of 2 workspaces resolves the ACTIVE workspace's id,
//       never a sibling's — the active workspaceId is passed straight to
//       the RPC as p_workspace_id;
//   (b) a NON-member workspaceId resolves NULL (the RPC's deny path);
//   (c) an UNDEFINED claim resolves the caller's SOLO workspace
//       (= userId per ADR-038 N2), never a sibling.

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: mockRpc })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

describe("resolveInstallationId (workspace-scoped, RPC-only)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("(a) resolves the ACTIVE workspace's installation id via the RPC, never a sibling", async () => {
    mockRpc.mockResolvedValue({ data: 555, error: null });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1", "ws-active");
    expect(result).toBe(555);
    // The credential read goes through the definer RPC keyed on the
    // ACTIVE workspace — not a direct table read, not a sibling scan.
    expect(mockRpc).toHaveBeenCalledWith("resolve_workspace_installation_id", {
      p_workspace_id: "ws-active",
    });
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });

  it("(b) returns null for a NON-member workspaceId (RPC deny path)", async () => {
    // The definer RPC returns NULL when the caller is not a member.
    mockRpc.mockResolvedValue({ data: null, error: null });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1", "ws-not-mine");
    expect(result).toBeNull();
    expect(mockRpc).toHaveBeenCalledWith("resolve_workspace_installation_id", {
      p_workspace_id: "ws-not-mine",
    });
  });

  it("(c) undefined claim resolves the caller's SOLO workspace (= userId), never a sibling", async () => {
    mockRpc.mockResolvedValue({ data: 777, error: null });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-solo");
    expect(result).toBe(777);
    // Defaulted p_workspace_id to the userId — the solo workspace id.
    expect(mockRpc).toHaveBeenCalledWith("resolve_workspace_installation_id", {
      p_workspace_id: "user-solo",
    });
  });

  it("null claim also defaults to the solo workspace", async () => {
    mockRpc.mockResolvedValue({ data: 777, error: null });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    await resolveInstallationId("user-solo", null);
    expect(mockRpc).toHaveBeenCalledWith("resolve_workspace_installation_id", {
      p_workspace_id: "user-solo",
    });
  });

  it("returns null and reports fallback when the RPC errors", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom" } });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1", "ws-1");
    expect(result).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "resolve-installation-id" }),
    );
  });

  it("returns null and reports fallback on RuntimeAuthError", async () => {
    const { RuntimeAuthError } = await import("@/lib/supabase/tenant");
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    const { reportSilentFallback } = await import("@/server/observability");

    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new RuntimeAuthError("jwt_mint", "token expired");
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1", "ws-1");
    expect(result).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({ feature: "resolve-installation-id" }),
    );
  });

  it("re-throws non-RuntimeAuthError errors", async () => {
    const { getFreshTenantClient } = await import("@/lib/supabase/tenant");
    vi.mocked(getFreshTenantClient).mockImplementationOnce(async () => {
      throw new Error("unexpected failure");
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    await expect(resolveInstallationId("user-1", "ws-1")).rejects.toThrow(
      "unexpected failure",
    );
  });
});
