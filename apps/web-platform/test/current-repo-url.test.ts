import { describe, it, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

// ADR-044 read-cutover: getCurrentRepoUrl now reads workspaces.repo_url for
// the caller's ACTIVE workspace (resolved internally from
// user_session_state, fallback solo = userId), NOT users.repo_url. Reads
// come from `workspaces` only — no users fallback (dual-ownership trap).

const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

const { mockResolveWs } = vi.hoisted(() => ({ mockResolveWs: vi.fn() }));
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveWs,
}));

describe("getCurrentRepoUrl (workspace read-cutover)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockResolveWs.mockImplementation(async (userId: string) => userId);
  });

  it("reads workspaces.repo_url for the internally-resolved active workspace", async () => {
    mockResolveWs.mockResolvedValueOnce("ws-active");
    const chain = mockQueryChain({ repo_url: "https://github.com/foo/bar" });
    mockFrom.mockReturnValue(chain);

    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    const result = await getCurrentRepoUrl("user-1");

    expect(result).toBe("https://github.com/foo/bar");
    expect(mockFrom).toHaveBeenCalledWith("workspaces");
    expect(chain.eq).toHaveBeenCalledWith("id", "ws-active");
  });

  it("normalizes the stored repo_url on return", async () => {
    const chain = mockQueryChain({ repo_url: "HTTPS://GitHub.com/Foo/Bar.git/" });
    mockFrom.mockReturnValue(chain);

    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    expect(await getCurrentRepoUrl("user-1")).toBe("https://github.com/Foo/Bar");
  });

  it("an explicit workspaceId override bypasses internal resolution", async () => {
    const chain = mockQueryChain({ repo_url: "https://github.com/x/y" });
    mockFrom.mockReturnValue(chain);

    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    await getCurrentRepoUrl("user-1", "ws-explicit");

    expect(mockResolveWs).not.toHaveBeenCalled();
    expect(chain.eq).toHaveBeenCalledWith("id", "ws-explicit");
  });

  it("returns null when the active workspace has no repo", async () => {
    mockFrom.mockReturnValue(mockQueryChain({ repo_url: null }));
    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    expect(await getCurrentRepoUrl("user-1")).toBeNull();
  });

  it("returns null and reports fallback on a transient DB error", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    mockFrom.mockReturnValue(mockQueryChain(null, { message: "boom" }));

    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    expect(await getCurrentRepoUrl("user-1")).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "repo-scope" }),
    );
  });

  it("returns null on RuntimeAuthError from tenant mint, mirrored at WARNING (transient, retryable)", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    vi.mocked(getFreshTenantClient).mockRejectedValueOnce(
      new RuntimeAuthError("jwt_mint", "expired"),
    );
    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    expect(await getCurrentRepoUrl("user-1")).toBeNull();
    // The tenant-mint blip is a transient retryable auth failure on a hot
    // reconnect path — WARNING, not error (the highest-volume contributor to
    // the stream-replay false-positive flood; #5290 follow-up).
    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "repo-scope",
        op: "read-current-repo-url.tenant-mint",
      }),
    );
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("never reads the users table (no dual-ownership fallback)", async () => {
    mockFrom.mockReturnValue(mockQueryChain({ repo_url: "https://github.com/a/b" }));
    const { getCurrentRepoUrl } = await import("@/server/current-repo-url");
    await getCurrentRepoUrl("user-1");
    expect(mockFrom).not.toHaveBeenCalledWith("users");
  });
});

// The degrade-aware variant surfaces WHY the url is null so a consumer (the
// Workstream board accessor) can tell a transient degrade apart from an honest
// "no repo connected". getCurrentRepoUrl stays a thin `.url` wrapper — every
// existing consumer contract is unchanged (AC4).
describe("readCurrentRepoUrlResult (degrade-aware variant)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockResolveWs.mockImplementation(async (userId: string) => userId);
  });

  it("returns {url, degraded:false} for a connected repo", async () => {
    const chain = mockQueryChain({ repo_url: "HTTPS://GitHub.com/Foo/Bar.git/" });
    mockFrom.mockReturnValue(chain);
    const { readCurrentRepoUrlResult } = await import("@/server/current-repo-url");
    expect(await readCurrentRepoUrlResult("user-1")).toEqual({
      url: "https://github.com/Foo/Bar",
      degraded: false,
    });
  });

  it("returns {url:null, degraded:false} for an honest no-repo (not a degrade)", async () => {
    mockFrom.mockReturnValue(mockQueryChain({ repo_url: null }));
    const { readCurrentRepoUrlResult } = await import("@/server/current-repo-url");
    expect(await readCurrentRepoUrlResult("user-1")).toEqual({
      url: null,
      degraded: false,
    });
  });

  it("returns {url:null, degraded:true} on a workspaces query error, mirrored at ERROR level", async () => {
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    mockFrom.mockReturnValue(mockQueryChain(null, { message: "boom" }));
    const { readCurrentRepoUrlResult } = await import("@/server/current-repo-url");
    expect(await readCurrentRepoUrlResult("user-1")).toEqual({
      url: null,
      degraded: true,
    });
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "repo-scope" }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("returns {url:null, degraded:true} on a RuntimeAuthError, mirrored at WARN level (split preserved)", async () => {
    const { RuntimeAuthError, getFreshTenantClient } = await import(
      "@/lib/supabase/tenant"
    );
    const { reportSilentFallback, warnSilentFallback } = await import(
      "@/server/observability"
    );
    vi.mocked(getFreshTenantClient).mockRejectedValueOnce(
      new RuntimeAuthError("jwt_mint", "expired"),
    );
    const { readCurrentRepoUrlResult } = await import("@/server/current-repo-url");
    expect(await readCurrentRepoUrlResult("user-1")).toEqual({
      url: null,
      degraded: true,
    });
    // WARN-vs-ERROR split preserved (ADR-059): tenant-mint is WARN, not ERROR.
    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "repo-scope",
        op: "read-current-repo-url.tenant-mint",
      }),
    );
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});
