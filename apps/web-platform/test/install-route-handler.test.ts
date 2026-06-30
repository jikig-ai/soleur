import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock modules BEFORE importing the route handler
// ---------------------------------------------------------------------------

const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();
const mockRpc = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  }),
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { admin: { getUserById: mockAdminGetUserById } },
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

vi.mock("@/server/github-app", () => ({
  verifyInstallationOwnership: vi.fn(),
  getInstallationAccount: vi.fn(),
}));

// ADR-044 PR-2: the install write lands on the active `workspaces` row via the
// service client. resolveActiveWorkspace defaults to the solo identity
// (workspaceId === user.id); writeRepoColsToWorkspace is the authoritative write.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: vi.fn(),
}));
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: vi.fn(),
}));

import { POST } from "../app/api/repo/install/route";
import { verifyInstallationOwnership as mockVerifyOwnership, getInstallationAccount as mockGetInstallationAccount } from "../server/github-app";
import { resolveActiveWorkspace as mockResolveActiveWorkspace } from "../server/workspace-resolver";
import { writeRepoColsToWorkspace as mockWriteRepoColsToWorkspace } from "../server/workspace-repo-mirror";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(body: Record<string, unknown>) {
  return new Request("https://app.soleur.ai/api/repo/install", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
}

/** Mock the admin getUserById response with the given identities list. */
function mockIdentitiesQuery(
  userId: string,
  identities: Array<{ provider: string; identity_data: Record<string, unknown> }> | null,
) {
  mockAdminGetUserById.mockResolvedValue({
    data: {
      user: identities === null ? null : { id: userId, identities },
    },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/repo/install — identity resolution", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    (mockVerifyOwnership as ReturnType<typeof vi.fn>).mockResolvedValue({
      verified: true,
    });
    // Active workspace resolves to the solo identity by default.
    vi.mocked(mockResolveActiveWorkspace).mockImplementation(
      async (userId: string) => ({ ok: true, workspaceId: userId }) as never,
    );
    // Owner-gate rpc("is_workspace_owner") passes by default.
    mockRpc.mockResolvedValue({ data: true, error: null });
    // Authoritative workspaces write succeeds by default.
    vi.mocked(mockWriteRepoColsToWorkspace).mockResolvedValue(undefined as never);
  });

  test("succeeds when user.identities is null but admin API has GitHub record", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-abc",
          identities: null,
          app_metadata: { providers: ["email", "github"] },
        },
      },
    });

    mockIdentitiesQuery("user-abc", [
      { provider: "email", identity_data: {} },
      { provider: "github", identity_data: { user_name: "deruelle" } },
    ]);

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);

    // ADR-044 PR-2: the installation lands on the active workspaces row, keyed
    // on the resolved solo id (=== user.id) — NOT via users.update.
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledWith(
      expect.anything(),
      "user-abc",
      { github_installation_id: 100 },
      { throwOnError: true },
    );
  });

  test("email-only user via admin API: succeeds when installation exists", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-xyz",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-xyz", [
      { provider: "email", identity_data: {} },
    ]);
    // Installation exists
    vi.mocked(mockGetInstallationAccount).mockResolvedValue({
      login: "someuser",
      id: 1,
      type: "User",
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledWith(
      expect.anything(),
      "user-xyz",
      { github_installation_id: 100 },
      { throwOnError: true },
    );
  });

  test("succeeds when admin API returns GitHub identity (standard flow)", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-def",
          identities: [
            { provider: "github", identity_data: { user_name: "alice" } },
          ],
          app_metadata: { providers: ["github"] },
        },
      },
    });

    mockIdentitiesQuery("user-def", [
      { provider: "github", identity_data: { user_name: "alice" } },
    ]);

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("email-only user: stores installation when it exists", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-email-only",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-email-only", null);
    // getInstallationAccount succeeds — installation exists
    vi.mocked(mockGetInstallationAccount).mockResolvedValue({
      login: "someuser",
      id: 1,
      type: "User",
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledWith(
      expect.anything(),
      "user-email-only",
      { github_installation_id: 100 },
      { throwOnError: true },
    );
  });

  test("email-only user: returns 404 when installation does not exist", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-email-only-2",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-email-only-2", null);
    // getInstallationAccount throws — installation not found
    vi.mocked(mockGetInstallationAccount).mockRejectedValue(new Error("Installation not found"));

    const res = await POST(makeRequest({ installationId: 999 }));
    expect(res.status).toBe(404);
  });

  test("returns 500 with descriptive error when getUserById throws", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-crash",
          identities: null,
          app_metadata: { providers: ["email", "github"] },
        },
      },
    });

    mockAdminGetUserById.mockRejectedValue(
      new Error("localStorage is not defined"),
    );

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to resolve/i);
  });

  // --- ADR-044 PR-2: active-workspace resolution + owner-gate + write cutover ---

  function mockGithubUser(id: string) {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id,
          identities: [
            { provider: "github", identity_data: { user_name: "alice" } },
          ],
          app_metadata: { providers: ["github"] },
        },
      },
    });
    mockIdentitiesQuery(id, [
      { provider: "github", identity_data: { user_name: "alice" } },
    ]);
  }

  test("returns 503 when the active workspace cannot be resolved (db-error)", async () => {
    mockGithubUser("user-503");
    vi.mocked(mockResolveActiveWorkspace).mockResolvedValue({
      ok: false,
      reason: "db-error",
    } as never);

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(503);
    // Fail-closed before any credential write.
    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
  });

  test("returns 403 when the caller is not the workspace owner (owner-gate)", async () => {
    mockGithubUser("user-403");
    mockRpc.mockResolvedValue({ data: false, error: null });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(403);
    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
  });

  test("returns 500 when the workspaces write fails (fail-closed)", async () => {
    mockGithubUser("user-write-fail");
    vi.mocked(mockWriteRepoColsToWorkspace).mockRejectedValue(
      new Error("0-row no-op"),
    );

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to store/i);
  });

  test("never performs a users.update({ github_installation_id }) write", async () => {
    mockGithubUser("user-no-users-update");

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    // The legacy users-row write must be gone — the only write goes through the
    // workspaces mirror. serviceClient.from() must never be invoked for "users".
    expect(mockServiceFrom).not.toHaveBeenCalledWith("users");
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledTimes(1);
  });

  test("owner-gate rpc is invoked on the tenant client keyed on the active workspace", async () => {
    mockGithubUser("user-rpc-args");

    await POST(makeRequest({ installationId: 100 }));
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: "user-rpc-args",
      p_user_id: "user-rpc-args",
    });
  });
});
