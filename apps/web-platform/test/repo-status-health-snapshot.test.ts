import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock Supabase before importing the route
// ---------------------------------------------------------------------------

// ADR-044 PR-2 (#5462): the repo-connection columns are authoritative on the
// ACTIVE `workspaces` row. The route reads them via
// `workspaces.select(...).eq("id", activeWorkspaceId).maybeSingle()`
// (`mockWorkspaceMaybeSingle`) and `health_snapshot` via
// `users.select("health_snapshot").eq("id", user.id).maybeSingle()`
// (`mockUserMaybeSingle`), both in a Promise.all. The active id is resolved via
// the mocked `resolveCurrentWorkspaceId` (defaults to the caller's own id).
const {
  mockResolveActiveWorkspacePath,
  mockResolveCurrentWorkspaceId,
  mockExistsSync,
  mockWorkspaceMaybeSingle,
  mockUserMaybeSingle,
  mockConvMaybeSingle,
} = vi.hoisted(() => ({
  mockResolveActiveWorkspacePath: vi.fn(),
  mockResolveCurrentWorkspaceId: vi.fn(),
  mockExistsSync: vi.fn((_p?: unknown) => false),
  mockWorkspaceMaybeSingle: vi.fn(),
  mockUserMaybeSingle: vi.fn(),
  mockConvMaybeSingle: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => {
  // conversations: select → eq → eq → eq → order → limit → maybeSingle
  const convChain = {
    select: vi.fn(() => convChain),
    eq: vi.fn(() => convChain),
    order: vi.fn(() => convChain),
    limit: vi.fn(() => convChain),
    maybeSingle: mockConvMaybeSingle,
  };
  // workspaces: select → eq("id", …) → maybeSingle (repo cols)
  const wsChain = {
    select: vi.fn(() => wsChain),
    eq: vi.fn(() => wsChain),
    maybeSingle: mockWorkspaceMaybeSingle,
  };
  // users: select("health_snapshot") → eq("id", …) → maybeSingle
  const userChain = {
    select: vi.fn(() => userChain),
    eq: vi.fn(() => userChain),
    maybeSingle: mockUserMaybeSingle,
  };

  const mockFrom = vi.fn((table: string) => {
    if (table === "conversations") return convChain;
    if (table === "workspaces") return wsChain;
    if (table === "users") return userChain;
    throw new Error(`unexpected service-role table ${table}`);
  });

  return {
    createClient: vi.fn(async () => ({
      auth: {
        getUser: vi.fn(async () => ({
          data: { user: { id: "user-123" } },
        })),
      },
    })),
    createServiceClient: vi.fn(() => ({
      from: mockFrom,
    })),
  };
});

// #5005 — `hasKnowledgeBase` is computed from the resolver's ACTIVE workspace
// path, not the caller's own `users.workspace_path` column. ADR-044 PR-2: the
// repo cols are read from the active `workspaces` row keyed on
// `resolveCurrentWorkspaceId` (defaults to the caller's own id here).
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

vi.mock("fs", async () => {
  const actual = await vi.importActual<typeof import("fs")>("fs");
  return { ...actual, existsSync: mockExistsSync };
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GET /api/repo/status — health_snapshot", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockExistsSync.mockReturnValue(false);
    mockResolveActiveWorkspacePath.mockResolvedValue("/workspaces/user-123");
    // Active workspace defaults to the caller's own id (solo).
    mockResolveCurrentWorkspaceId.mockResolvedValue("user-123");
  });

  it("includes healthSnapshot and syncConversationId in response when stored", async () => {
    const snapshot = {
      scannedAt: "2026-04-10T00:00:00.000Z",
      category: "developing",
      signals: {
        detected: [{ id: "tests", label: "Test suite" }],
        missing: [{ id: "ci", label: "CI/CD" }],
      },
      recommendations: ["Set up CI/CD."],
      kbExists: false,
    };

    // Repo cols live on the active `workspaces` row (ADR-044 PR-2).
    mockWorkspaceMaybeSingle.mockResolvedValue({
      data: {
        repo_url: "https://github.com/user/repo",
        repo_status: "ready",
        repo_last_synced_at: "2026-04-10T00:00:00.000Z",
        repo_error: null,
      },
      error: null,
    });
    // health_snapshot stays on `users`.
    mockUserMaybeSingle.mockResolvedValue({
      data: { health_snapshot: snapshot },
      error: null,
    });

    // Active sync conversation exists
    mockConvMaybeSingle.mockResolvedValue({
      data: { id: "conv-abc" },
      error: null,
    });

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toEqual(snapshot);
    expect(body.syncConversationId).toBe("conv-abc");
    expect(body.status).toBe("ready");
    expect(body.repoUrl).toBe("https://github.com/user/repo");
    expect(body.lastSyncedAt).toBe("2026-04-10T00:00:00.000Z");
    expect(mockResolveCurrentWorkspaceId).toHaveBeenCalledWith(
      "user-123",
      expect.anything(),
    );
  });

  it("returns syncConversationId as null when no active sync conversation (#1816)", async () => {
    mockWorkspaceMaybeSingle.mockResolvedValue({
      data: {
        repo_url: "https://github.com/user/repo",
        repo_status: "ready",
        repo_last_synced_at: "2026-04-10T00:00:00.000Z",
        repo_error: null,
      },
      error: null,
    });
    mockUserMaybeSingle.mockResolvedValue({
      data: { health_snapshot: null },
      error: null,
    });

    // No active sync conversation
    mockConvMaybeSingle.mockResolvedValue({
      data: null,
      error: null,
    });

    const { GET } = await import(
      "@/app/api/repo/status/route"
    );

    const res = await GET();
    const body = await res.json();

    expect(body.healthSnapshot).toBeNull();
    expect(body.syncConversationId).toBeNull();
  });

  it("computes hasKnowledgeBase from the resolver's ACTIVE path for a stale-own-row caller (#5005)", async () => {
    // Post-ADR-044 account: the `users` row has NO `workspace_path`, but the
    // active workspace exists on disk with a knowledge-base/ dir. The flag must
    // be true — computed from the resolver, not the (absent) own-row column.
    const ACTIVE_PATH = "/workspaces/active-ws-divergent";
    mockResolveActiveWorkspacePath.mockResolvedValue(ACTIVE_PATH);
    mockExistsSync.mockImplementation((p: unknown) =>
      String(p) === `${ACTIVE_PATH}/knowledge-base`,
    );

    mockWorkspaceMaybeSingle.mockResolvedValue({
      data: {
        repo_url: "https://github.com/user/repo",
        repo_status: "ready",
        repo_last_synced_at: null,
        repo_error: null,
      },
      error: null,
    });
    mockUserMaybeSingle.mockResolvedValue({
      data: { health_snapshot: null },
      error: null,
    });
    mockConvMaybeSingle.mockResolvedValue({ data: null, error: null });

    const { GET } = await import("@/app/api/repo/status/route");
    const res = await GET();
    const body = await res.json();

    expect(body.hasKnowledgeBase).toBe(true);
    expect(mockResolveActiveWorkspacePath).toHaveBeenCalledWith(
      "user-123",
      expect.anything(),
    );
  });
});
