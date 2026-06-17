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
  mockResolveActiveWorkspace,
  mockWriteRepoColsToWorkspace,
  mockAbortAllWorkspaceMemberSessions,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockDeleteWorkspace: vi.fn(),
  mockIsAllowed: vi.fn(),
  mockRpc: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
  mockWriteRepoColsToWorkspace: vi.fn(),
  mockAbortAllWorkspaceMemberSessions: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace,
}));

// ADR-044 PR-2: the route resolves its target workspace via the
// membership-verified resolver (session claim, never request input). Control
// its return per-test; db-error must fail-closed to 503.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: mockResolveActiveWorkspace,
}));

// ADR-044 PR-2: the repo-column CLEAR is now authoritative on the `workspaces`
// row, written via the dynamically-imported mirror helper. Mock it so we can
// assert the exact (client, id, patch, opts) and exercise the fail-closed path.
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: mockWriteRepoColsToWorkspace,
}));

// ADR-044 PR-2 / P0-6: live member agent sessions are aborted before teardown.
vi.mock("@/server/agent-session-registry", () => ({
  abortAllWorkspaceMemberSessions: mockAbortAllWorkspaceMemberSessions,
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
const TEAM_WORKSPACE_ID = "11111111-2222-3333-4444-555555555555";

/**
 * Wire the service-role `workspaces` table mock chain.
 *
 * The route reads `workspaces.select("repo_status").eq("id", activeId).single()`
 * for the cloning-guard (ADR-044 PR-2: was `users`). Repo-column CLEAR and the
 * readiness reset on `users` are handled by separate mocks
 * (`writeRepoColsToWorkspace`, `mockUpdate`).
 *
 * Returns `mockUpdate` so callers can assert the `users.update(...)` readiness
 * reset (solo path) — or assert it was NOT called (team path).
 */
function setupServiceMocks(opts: {
  repoStatus?: string;
  selectError?: { message: string } | null;
  updateError?: { message: string } | null;
}) {
  const { repoStatus = "ready", selectError = null, updateError = null } = opts;

  const selectChain = mockQueryChain(
    selectError ? null : { repo_status: repoStatus },
    selectError,
  );

  const mockUpdateEq = vi.fn().mockResolvedValue({ error: updateError });
  const mockUpdate = vi.fn(() => ({ eq: mockUpdateEq }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "workspaces") {
      // Only the cloning-guard select hits this table directly; the CLEAR goes
      // through the mocked writeRepoColsToWorkspace helper.
      return { select: selectChain.select };
    }
    if (table === "users") {
      // Solo-only readiness reset (health_snapshot / workspace_status).
      return { update: mockUpdate };
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
    // ADR-044 PR-1 owner-gate: default to owner. The non-owner case overrides.
    mockRpc.mockResolvedValue({ data: true, error: null });
    // ADR-044 PR-2: default the resolver to SOLO (active == caller), so every
    // existing case (cloning-guard, fail-closed clear, idempotency) runs the
    // solo path unless a team test overrides it.
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: TEST_USER_ID,
    });
    // Default the credential-clear helper to succeed.
    mockWriteRepoColsToWorkspace.mockResolvedValue(undefined);
  });

  // -------------------------------------------------------------------------
  // ADR-044 PR-2 team write-cutover
  // -------------------------------------------------------------------------

  test("team workspace active + owner → proceeds and tears down the TEAM workspace (200)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: TEAM_WORKSPACE_ID,
    });
    const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);

    // Owner-gate is keyed to the RESOLVED active (team) id, NOT user.id.
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEAM_WORKSPACE_ID,
      p_user_id: TEST_USER_ID,
    });

    // The repo columns are cleared AUTHORITATIVELY on the team workspaces row.
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledWith(
      expect.anything(),
      TEAM_WORKSPACE_ID,
      {
        github_installation_id: null,
        repo_url: null,
        repo_status: "not_connected",
        repo_last_synced_at: null,
        repo_error: null,
      },
      { throwOnError: true },
    );

    // Live member sessions aborted before teardown, keyed to the team id.
    expect(mockAbortAllWorkspaceMemberSessions).toHaveBeenCalledWith(
      TEAM_WORKSPACE_ID,
      TEST_USER_ID,
    );

    // The team directory is torn down (NOT the caller's solo dir).
    expect(mockDeleteWorkspace).toHaveBeenCalledWith(TEAM_WORKSPACE_ID);

    // CRITICAL: the team path must NOT reset the caller's `users` readiness —
    // doing so corrupts their personal solo readiness and other owned teams.
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  test("team workspace active + NON-owner → 403 before any mutation (owner-gate)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: TEAM_WORKSPACE_ID,
    });
    mockRpc.mockResolvedValueOnce({ data: false, error: null });
    const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error).toMatch(/owner/i);

    // Owner-gate keyed to the RESOLVED active (team) id.
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEAM_WORKSPACE_ID,
      p_user_id: TEST_USER_ID,
    });

    // Short-circuit BEFORE any mutation.
    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
    expect(mockAbortAllWorkspaceMemberSessions).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  test("resolver fails (db-error) → 503 fail-closed, no mutation, no teardown", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: false,
      reason: "db-error",
    });
    const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error).toMatch(/active workspace/i);

    // A db-error at this destructive boundary must NEVER silently tear down the
    // caller's solo workspace under a team claim — fail closed before the
    // owner-gate AND every mutation.
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
    expect(mockAbortAllWorkspaceMemberSessions).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  test("solo active workspace → owner-gate keyed to user.id, resets solo readiness, tears down solo dir (200)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    // resolver defaults to solo (workspaceId === user.id).
    const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);

    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEST_USER_ID,
      p_user_id: TEST_USER_ID,
    });

    // Authoritative CLEAR on the caller's own (solo) workspaces row.
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalledWith(
      expect.anything(),
      TEST_USER_ID,
      {
        github_installation_id: null,
        repo_url: null,
        repo_status: "not_connected",
        repo_last_synced_at: null,
        repo_error: null,
      },
      { throwOnError: true },
    );

    // Solo readiness reset on `users` — ONLY the provisioning/readiness columns,
    // NEVER a repo column (those are relocated to `workspaces`).
    expect(mockUpdate).toHaveBeenCalledWith({
      health_snapshot: null,
      workspace_status: "provisioning",
    });

    expect(mockAbortAllWorkspaceMemberSessions).toHaveBeenCalledWith(
      TEST_USER_ID,
      TEST_USER_ID,
    );
    expect(mockDeleteWorkspace).toHaveBeenCalledWith(TEST_USER_ID);
  });

  // -------------------------------------------------------------------------
  // Auth / CSRF / rate-limit gates
  // -------------------------------------------------------------------------

  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);

    // No resolution / mutation before auth.
    expect(mockResolveActiveWorkspace).not.toHaveBeenCalled();
  });

  test("returns 429 when rate limited", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
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

  // -------------------------------------------------------------------------
  // Cloning-guard / db-error / fail-closed clear (adapted to workspaces row)
  // -------------------------------------------------------------------------

  test("returns 409 when the active workspace repo is currently cloning", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupServiceMocks({ repoStatus: "cloning" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error).toMatch(/in progress/i);

    // Guard precedes the destructive clear + teardown.
    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
  });

  test("returns 500 when the workspaces cloning-guard select fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupServiceMocks({ selectError: { message: "database unreachable" } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);

    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
  });

  test("returns 500 when the owner-gate rpc errors", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    mockRpc.mockResolvedValueOnce({ data: null, error: { message: "rpc boom" } });
    setupServiceMocks({ repoStatus: "ready" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);

    expect(mockWriteRepoColsToWorkspace).not.toHaveBeenCalled();
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
  });

  test("returns 500 when the credential-clear fails CLOSED (ADR-044, helper throws)", async () => {
    // The read path is workspaces-only; a silently-failed clear would leave
    // github_installation_id + repo_url live (caller appears connected, agent
    // can still act under the revoked grant). The helper throws on db-error OR
    // 0-row no-op, so the route surfaces a 500 and the (idempotent) disconnect
    // is retried rather than falsely reporting success.
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupServiceMocks({ repoStatus: "ready" });
    mockWriteRepoColsToWorkspace.mockRejectedValue(
      new Error("mirror write failed"),
    );
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);

    // Failed CLOSED: teardown does NOT proceed after a failed credential clear.
    expect(mockDeleteWorkspace).not.toHaveBeenCalled();
  });

  test("workspace cleanup failure still returns 200 (best-effort)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupServiceMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockRejectedValue(
      new Error("Directory already removed"),
    );

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);

    // The credential WAS cleared before the best-effort teardown failed.
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalled();
  });

  test("returns 200 idempotently when the active workspace has no connected repo", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupServiceMocks({ repoStatus: "not_connected" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);

    // Still clears authoritatively (idempotent no-op clear) and tears down.
    expect(mockWriteRepoColsToWorkspace).toHaveBeenCalled();
    expect(mockDeleteWorkspace).toHaveBeenCalledWith(TEST_USER_ID);
  });

  // -------------------------------------------------------------------------
  // ADR-044 exit criterion: ZERO repo-column writes to `users` on ANY path.
  // The whole point of PR-2 — repo state is authoritative on `workspaces`.
  // -------------------------------------------------------------------------

  test("NO repo-column write to `users` occurs on ANY path (solo + team)", async () => {
    const repoCols = ["repo_url", "github_installation_id", "repo_error"];

    // Solo path.
    {
      mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
      const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });
      mockDeleteWorkspace.mockResolvedValue(undefined);

      const res = await DELETE(makeRequest());
      expect(res.status).toBe(200);

      for (const call of mockUpdate.mock.calls) {
        const patch = ((call as unknown[])[0] ?? {}) as Record<string, unknown>;
        for (const col of repoCols) {
          expect(patch).not.toHaveProperty(col);
        }
      }
    }

    // Team path — `users.update` must not be called at all.
    {
      vi.clearAllMocks();
      mockIsAllowed.mockReturnValue(true);
      mockRpc.mockResolvedValue({ data: true, error: null });
      mockWriteRepoColsToWorkspace.mockResolvedValue(undefined);
      mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
      mockResolveActiveWorkspace.mockResolvedValue({
        ok: true,
        workspaceId: TEAM_WORKSPACE_ID,
      });
      const { mockUpdate } = setupServiceMocks({ repoStatus: "ready" });
      mockDeleteWorkspace.mockResolvedValue(undefined);

      const res = await DELETE(makeRequest());
      expect(res.status).toBe(200);
      expect(mockUpdate).not.toHaveBeenCalled();
    }
  });
});
