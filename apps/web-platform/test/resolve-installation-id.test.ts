import { describe, it, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

const { mockTenantFrom, mockServiceFrom } = vi.hoisted(() => ({
  mockTenantFrom: vi.fn(),
  mockServiceFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockTenantFrom })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

describe("extractGitHubOwner", () => {
  it("extracts owner from standard GitHub URL", async () => {
    const { extractGitHubOwner } = await import(
      "@/server/resolve-installation-id"
    );
    expect(extractGitHubOwner("https://github.com/jikig-ai/soleur")).toBe(
      "jikig-ai",
    );
  });

  it("extracts owner from different repo under same org", async () => {
    const { extractGitHubOwner } = await import(
      "@/server/resolve-installation-id"
    );
    expect(extractGitHubOwner("https://github.com/jikig-ai/chatte")).toBe(
      "jikig-ai",
    );
  });

  it("returns null for URL without repo segment", async () => {
    const { extractGitHubOwner } = await import(
      "@/server/resolve-installation-id"
    );
    expect(extractGitHubOwner("https://github.com/single")).toBeNull();
  });

  it("returns null for non-GitHub URL", async () => {
    const { extractGitHubOwner } = await import(
      "@/server/resolve-installation-id"
    );
    expect(extractGitHubOwner("https://gitlab.com/jikig-ai/soleur")).toBeNull();
  });

  it("returns null for empty string", async () => {
    const { extractGitHubOwner } = await import(
      "@/server/resolve-installation-id"
    );
    expect(extractGitHubOwner("")).toBeNull();
  });
});

describe("resolveInstallationId", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns own installation ID when present", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: 555,
        repo_url: "https://github.com/jikig-ai/soleur",
      }),
    );

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBe(555);
    expect(mockServiceFrom).not.toHaveBeenCalled();
  });

  it("resolves from sibling with same GitHub org", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: "https://github.com/jikig-ai/soleur",
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([{ user_id: "sibling-1" }]);
    const usersChain = mockQueryChain({
      github_installation_id: 122213433,
    });

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      if (table === "users") return usersChain;
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBe(122213433);

    expect(usersChain.ilike).toHaveBeenCalledWith(
      "repo_url",
      "https://github.com/jikig-ai/%",
    );
  });

  it("resolves from sibling with same org but different case", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: "https://github.com/Jikig-AI/soleur",
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([{ user_id: "sibling-1" }]);
    const usersChain = mockQueryChain({
      github_installation_id: 122213433,
    });

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      if (table === "users") return usersChain;
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBe(122213433);

    expect(usersChain.ilike).toHaveBeenCalledWith(
      "repo_url",
      "https://github.com/Jikig-AI/%",
    );
  });

  it("does not resolve from sibling with different GitHub org", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: "https://github.com/jikig-ai/soleur",
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([{ user_id: "sibling-1" }]);
    const usersChain = mockQueryChain(null);

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      if (table === "users") return usersChain;
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBeNull();
  });

  it("returns null when no siblings exist", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: "https://github.com/jikig-ai/soleur",
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([]);

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBeNull();
  });

  it("returns null when caller has no repo_url", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: null,
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([{ user_id: "sibling-1" }]);
    const usersChain = mockQueryChain({
      github_installation_id: 999,
    });

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      if (table === "users") return usersChain;
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBe(999);
    expect(usersChain.ilike).not.toHaveBeenCalled();
  });

  it("handles non-GitHub URLs gracefully", async () => {
    mockTenantFrom.mockReturnValue(
      mockQueryChain({
        github_installation_id: null,
        repo_url: "https://gitlab.com/jikig-ai/soleur",
      }),
    );

    const memberChain = mockQueryChain({ workspace_id: "ws-1" });
    const siblingsChain = mockQueryChain([{ user_id: "sibling-1" }]);
    const usersChain = mockQueryChain({
      github_installation_id: 999,
    });

    let serviceCallCount = 0;
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "workspace_members") {
        serviceCallCount++;
        return serviceCallCount === 1 ? memberChain : siblingsChain;
      }
      if (table === "users") return usersChain;
      return mockQueryChain(null);
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBe(999);
    expect(usersChain.ilike).not.toHaveBeenCalled();
  });

  it("returns null and reports fallback on RuntimeAuthError", async () => {
    const { RuntimeAuthError } = await import("@/lib/supabase/tenant");
    const { reportSilentFallback } = await import("@/server/observability");

    mockTenantFrom.mockImplementation(() => {
      throw new RuntimeAuthError("token expired");
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    const result = await resolveInstallationId("user-1");
    expect(result).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(RuntimeAuthError),
      expect.objectContaining({ feature: "resolve-installation-id" }),
    );
  });

  it("re-throws non-RuntimeAuthError errors", async () => {
    mockTenantFrom.mockImplementation(() => {
      throw new Error("unexpected failure");
    });

    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    await expect(resolveInstallationId("user-1")).rejects.toThrow(
      "unexpected failure",
    );
  });
});
