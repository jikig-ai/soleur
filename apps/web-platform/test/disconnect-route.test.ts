import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockDeleteWorkspace,
  mockIsAllowed,
  mockRpc,
  mockTenantFrom,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockDeleteWorkspace: vi.fn(),
  mockIsAllowed: vi.fn(),
  mockRpc: vi.fn(),
  mockTenantFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
    // ADR-044 PR-2a: the tenant client now reads user_session_state via
    // resolveCurrentWorkspaceId (active-workspace guard). Defaulted to solo
    // in beforeEach so every existing test is a no-op for the new guard.
    from: mockTenantFrom,
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.com" })),
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "CSRF rejected" }), { status: 403 }),
  ),
}));

vi.mock("@/server/rate-limiter", () => ({
  SlidingWindowCounter: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
  ) {
    this.isAllowed = mockIsAllowed;
  }),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { DELETE } from "@/app/api/repo/disconnect/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(): Request {
  return new Request("https://app.soleur.com/api/repo/disconnect", {
    method: "DELETE",
    headers: { origin: "https://app.soleur.com" },
  });
}

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

/** Sets up Supabase mock chain for the users table. */
function setupUserMocks(opts: {
  repoStatus?: string;
  selectError?: { message: string } | null;
  updateError?: { message: string } | null;
  mirrorError?: { message: string } | null;
}) {
  const {
    repoStatus = "ready",
    selectError = null,
    updateError = null,
    mirrorError = null,
  } = opts;

  const selectChain = mockQueryChain(
    selectError ? null : { repo_status: repoStatus },
    selectError,
  );

  const mockUpdateEq = vi.fn().mockResolvedValue({ error: updateError });
  const mockUpdate = vi.fn(() => ({ eq: mockUpdateEq }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return { select: selectChain.select, update: mockUpdate };
    }
    // ADR-044: workspaces mirror write (mirrorRepoColsToSoloWorkspace).
    if (table === "workspaces") {
      return { update: () => ({ eq: async () => ({ error: mirrorError }) }) };
    }
    return {};
  });

  return { mockUpdate };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("DELETE /api/repo/disconnect", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsAllowed.mockReturnValue(true);
    // ADR-044 PR-1 owner-gate: default to owner (solo users always own
    // workspace_id=user.id). The non-owner case overrides per-test.
    mockRpc.mockResolvedValue({ data: true, error: null });
    // ADR-044 PR-2a: default the active-workspace resolver to SOLO
    // (current_workspace_id null → resolveCurrentWorkspaceId returns user.id),
    // so the team-workspace refusal guard is a no-op for every existing test.
    mockTenantFrom.mockReturnValue(
      mockQueryChain({ current_workspace_id: null }, null),
    );
  });

  test("returns 422 and refuses when a TEAM workspace is active (ADR-044 PR-2a confused-deputy guard)", async () => {
    const TEAM_WORKSPACE_ID = "11111111-2222-3333-4444-555555555555";
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    // Active workspace is a TEAM (≠ user.id). Team on-disk provisioning is
    // #4560/Phase-5; until then a disconnect would SILENTLY tear down the
    // caller's PERSONAL solo connection (confused deputy). Refuse explicitly.
    mockTenantFrom.mockReturnValue(
      mockQueryChain({ current_workspace_id: TEAM_WORKSPACE_ID }, null),
    );
    const { mockUpdate } = setupUserMocks({ repoStatus: "ready" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(422);
    const body = await res.json();
    expect(body.error).toMatch(/team workspace/i);

    // The refusal precedes the owner-gate AND every mutation.
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockUpdate).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
  });

  test("solo active workspace (current_workspace_id === user.id) is unaffected by the team guard", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockTenantFrom.mockReturnValue(
      mockQueryChain({ current_workspace_id: TEST_USER_ID }, null),
    );
    setupUserMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);
  });

  test("returns 403 when the caller is not the workspace owner (ADR-044 owner-gate)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockRpc.mockResolvedValueOnce({ data: false, error: null });
    setupUserMocks({ repoStatus: "ready" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(403);
    // The owner-gate must short-circuit BEFORE any mutation.
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
    // p_workspace_id MUST equal the mutated workspace (= user.id in PR-1).
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEST_USER_ID,
      p_user_id: TEST_USER_ID,
    });
  });

  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);
  });

  test("returns 429 when rate limited", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    mockIsAllowed.mockReturnValue(false);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(429);

    const body = await res.json();
    expect(body.error).toMatch(/too many/i);
  });

  test("returns 403 on CSRF rejection", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(403);
  });

  test("returns 409 when repo is currently cloning", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "cloning" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.error).toMatch(/in progress/i);
  });

  test("returns 500 when select query fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupUserMocks({ selectError: { message: "database unreachable" } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);
  });

  test("returns 200 and clears all repo fields on successful disconnect", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    const { mockUpdate } = setupUserMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);

    expect(mockUpdate).toHaveBeenCalledWith({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
      health_snapshot: null,
      workspace_path: "",
      workspace_status: "provisioning",
    });

    expect(mockDeleteWorkspace).toHaveBeenCalledWith(TEST_USER_ID);
  });

  test("workspace cleanup failure still returns 200 (best-effort)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockRejectedValue(new Error("Directory already removed"));

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("returns 500 when database update fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupUserMocks({ repoStatus: "ready", updateError: { message: "constraint violation" } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);
  });

  test("returns 500 when the workspaces mirror fails (credential-clear fails closed, ADR-044)", async () => {
    // The read path is workspaces-only; a silently-failed disconnect mirror
    // would leave github_installation_id + repo_url live. Disconnect must fail
    // closed so the (idempotent) operation is retried rather than reporting a
    // disconnect that left the credential readable.
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupUserMocks({ repoStatus: "ready", mirrorError: { message: "mirror write failed" } });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);
  });

  test("returns 200 idempotently when user has no connected repo", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "not_connected" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
  });
});
