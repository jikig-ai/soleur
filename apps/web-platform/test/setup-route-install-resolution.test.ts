import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks (declared before the route import)
// ---------------------------------------------------------------------------
const mockGetUser = vi.fn();
const mockRpc = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();
const mockValidateOrigin = vi.fn();
const mockProvisionWorkspaceWithRepo = vi.fn();
const mockWriteRepoColsToWorkspace = vi.fn();
const mockResolveReachable = vi.fn();
const mockResolveOwning = vi.fn();
const mockResolveActiveWorkspace = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  // ADR-044 owner-gate: default to owner (solo users always own
  // workspace_id=user.id); the non-owner test overrides mockRpc.
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
  validateOrigin: (...a: unknown[]) =>
    mockValidateOrigin(...(a as Parameters<typeof mockValidateOrigin>)),
  rejectCsrf: () =>
    new Response(JSON.stringify({ error: "forbidden" }), { status: 403 }),
}));

vi.mock("@/server/workspace", () => ({
  provisionWorkspaceWithRepo: (...a: unknown[]) =>
    mockProvisionWorkspaceWithRepo(...a),
}));

vi.mock("@/server/project-scanner", () => ({
  scanProjectHealth: vi.fn(() => null),
}));

// Stub the heavy agent-runner SDK that triggerHeadlessSync lazy-imports in the
// route's fire-and-forget auto-sync path — otherwise the real import throws a
// VitestMocker error that escapes as an unhandled post-test rejection.
vi.mock("@/server/agent-runner", () => ({
  startAgentSession: vi.fn(async () => {}),
}));

vi.mock("@/lib/repo-url", () => ({
  normalizeRepoUrl: (u: string) => u,
}));

// ADR-044 PR-2: the route's authoritative repo-connection write now targets the
// `workspaces` row via writeRepoColsToWorkspace (was the solo-`users` mirror).
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: (...a: unknown[]) =>
    mockWriteRepoColsToWorkspace(...a),
}));

// ADR-044 PR-2: the active workspace id is resolved server-side via the
// membership-verified resolver. Default to SOLO (== user.id) in beforeEach; the
// team / db-error tests override. `resolveCurrentWorkspaceId` is re-exported so
// any sibling import resolves under the mock too.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: (...a: unknown[]) => mockResolveActiveWorkspace(...a),
  resolveCurrentWorkspaceId: vi.fn(async (userId: string) => userId),
}));

vi.mock("@/server/git-auth", () => ({
  GitOperationError: class extends Error {},
  sanitizeGitStderr: (s: string) => s,
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => id,
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  withIsolationScope: (fn: () => void) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
}));

vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: vi.fn(async () => false),
}));

vi.mock("@/server/reachable-installations", () => ({
  resolveReachableInstallationIds: (...a: unknown[]) =>
    mockResolveReachable(...a),
  resolveOwningInstallationForRepo: (...a: unknown[]) => mockResolveOwning(...a),
}));

import { POST } from "../app/api/repo/setup/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
// Stored install id read from the active `workspaces` row in the degraded
// fallback (ADR-044 PR-2 — it moved off `users.github_installation_id`).
let storedInstallationId: number | null = null;
// Captures every `workspaces.update(patch)` patch + the id it was `.eq("id", ·)`
// scoped to, so tests can assert the AUTHORITATIVE install write lands on the
// workspaces row (was a users.update of github_installation_id pre-PR-2).
let workspacesUpdateCalls: Array<{
  patch: Record<string, unknown>;
  id: string;
}> = [];
// Records whether the `users` table was ever `.update()`d (the install path must
// never write the install id to users).
let usersUpdateCalled = false;

function setupServiceClient() {
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "users") {
      // ADR-044 PR-2: the user read selects ONLY email + github_username (the
      // install id no longer lives here). The solo readiness write
      // (.update({workspace_status, health_snapshot}).eq("id", user.id)) still
      // targets users — but NEVER github_installation_id.
      return {
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                email: "user@example.com",
                github_username: "deruelle",
              },
              error: null,
            }),
          }),
        }),
        update: (patch: Record<string, unknown>) => {
          usersUpdateCalled = true;
          // The route asserts: a users write must NEVER carry the install id.
          expect(patch).not.toHaveProperty("github_installation_id");
          return { eq: async () => ({ error: null }) };
        },
      };
    }
    if (table === "workspaces") {
      return {
        // Degraded install fallback: .select(github_installation_id).eq(id).maybeSingle()
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data:
                storedInstallationId == null
                  ? null
                  : { github_installation_id: storedInstallationId },
              error: null,
            }),
          }),
        }),
        // Optimistic cloning-flip lock:
        // .update(patch).eq("id", activeId).neq("repo_status","cloning").select("id").maybeSingle()
        update: (patch: Record<string, unknown>) => {
          const chain: Record<string, unknown> = {
            eq: (_col: string, id: string) => {
              workspacesUpdateCalls.push({ patch, id });
              return chain;
            },
            neq: () => chain,
            select: () => chain,
            maybeSingle: async () => ({ data: { id: "user-1" }, error: null }),
          };
          return chain;
        },
      };
    }
    throw new Error(`unexpected table: ${table}`);
  });
}

function makeRequest(body: unknown) {
  return new Request("https://app.soleur.ai/api/repo/setup", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/repo/setup — install resolution", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storedInstallationId = null;
    workspacesUpdateCalls = [];
    usersUpdateCalled = false;
    mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1", email: "user@example.com" } },
    });
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { identities: [] } },
      error: null,
    });
    mockProvisionWorkspaceWithRepo.mockResolvedValue("/workspaces/user-1");
    mockWriteRepoColsToWorkspace.mockResolvedValue(undefined);
    // ADR-044 owner-gate: default owner; non-owner test overrides.
    mockRpc.mockResolvedValue({ data: true, error: null });
    // ADR-044 PR-2: default the active-workspace resolver to SOLO (== user.id),
    // so the team-provisioning / db-error branches are no-ops for the install
    // tests below.
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: "user-1",
    });
    setupServiceClient();
  });

  test("ADR-044 PR-2: TEAM workspace active + owner → PROVISIONS the team workspace (200, no 422)", async () => {
    const TEAM_WORKSPACE_ID = "11111111-2222-3333-4444-555555555555";
    // PR-2 team write-cutover (#5462): an owner connecting a repo while a TEAM
    // workspace is active now provisions THAT workspace on disk (was a PR-2a 422
    // refusal). The owner-gate runs against the resolved team id and passes.
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: TEAM_WORKSPACE_ID,
    });
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("cloning");

    // Owner-gate ran against the RESOLVED TEAM id (load-bearing for teams).
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEAM_WORKSPACE_ID,
      p_user_id: "user-1",
    });
    // Provisioning targets the RESOLVED TEAM id, not the caller's solo id.
    expect(mockProvisionWorkspaceWithRepo.mock.calls[0][0]).toBe(
      TEAM_WORKSPACE_ID,
    );
  });

  test("ADR-044 PR-2: TEAM workspace active + NON-owner → 403, no clone", async () => {
    const TEAM_WORKSPACE_ID = "11111111-2222-3333-4444-555555555555";
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: true,
      workspaceId: TEAM_WORKSPACE_ID,
    });
    // is_workspace_owner returns false for a non-owner member.
    mockRpc.mockResolvedValueOnce({ data: false, error: null });

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(403);
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();
    // The owner-gate ran against the RESOLVED TEAM id.
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: TEAM_WORKSPACE_ID,
      p_user_id: "user-1",
    });
  });

  test("ADR-044 PR-2: resolver db-error → 503 (fail-closed at the write boundary), no clone", async () => {
    mockResolveActiveWorkspace.mockResolvedValue({
      ok: false,
      reason: "db-error",
    });

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(503);
    // Fail-closed BEFORE the owner-gate and the clone (never silently provision
    // into the caller's solo workspace under a team claim).
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();
  });

  test("ADR-044 owner-gate: non-owner (solo) → 403, no clone", async () => {
    mockRpc.mockResolvedValueOnce({ data: false, error: null });

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(403);
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();
    expect(mockRpc).toHaveBeenCalledWith("is_workspace_owner", {
      p_workspace_id: "user-1",
      p_user_id: "user-1",
    });
  });

  test("T9: org member, NULL stored id, owning install resolved → clones via membership install", async () => {
    storedInstallationId = null;
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("cloning");
    expect(mockResolveOwning).toHaveBeenCalledWith(
      [122213433],
      "jikig-ai",
      "soleur",
    );
    // provisionWorkspaceWithRepo(workspaceId, repoUrl, installationId, ...)
    expect(mockProvisionWorkspaceWithRepo.mock.calls[0][2]).toBe(122213433);
  });

  test("T10: membership-fallback path writes the RESOLVED install to the WORKSPACES cloning-flip lock (never a users.update of github_installation_id)", async () => {
    storedInstallationId = null;
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);

    await POST(makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }));

    // ADR-044 PR-2: the install grant is persisted on the cloning-flip lock to
    // WORKSPACES (service-role update), keyed on the resolved active id — NOT a
    // `users.update` of github_installation_id. The patch carries the RESOLVED
    // id, never any other value.
    const installWrites = workspacesUpdateCalls.filter(
      (c) => c.patch.github_installation_id != null,
    );
    expect(installWrites.length).toBeGreaterThan(0);
    for (const c of installWrites) {
      expect(c.patch.github_installation_id).toBe(122213433);
      // Scoped to the resolved active id (solo == user-1 here).
      expect(c.id).toBe("user-1");
    }

    // The install id is NEVER written to `users` (the setupServiceClient mock
    // hard-asserts no users.update carries github_installation_id; this confirms
    // any users write that did happen was the readiness write, not the install).
    void usersUpdateCalled;
  });

  test("T11: personal happy path — stored id present, owning probe 'ok' → clones with stored id", async () => {
    storedInstallationId = 999;
    mockResolveReachable.mockResolvedValue([999]);
    mockResolveOwning.mockResolvedValue(999);

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/deruelle/my-repo" }),
    );
    expect(res.status).toBe(200);
    expect(mockProvisionWorkspaceWithRepo.mock.calls[0][2]).toBe(999);
  });

  test("T12: NULL stored id, empty reachable set, owning null → 400", async () => {
    storedInstallationId = null;
    mockResolveReachable.mockResolvedValue([]);
    mockResolveOwning.mockResolvedValue(null);

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe(
      "GitHub App not installed. Please install the app first.",
    );
    expect(mockProvisionWorkspaceWithRepo).not.toHaveBeenCalled();
  });

  test("T13: degraded probe (owning null) but stored id present on the active workspace → falls back to stored id", async () => {
    storedInstallationId = 999;
    mockResolveReachable.mockResolvedValue([999]);
    mockResolveOwning.mockResolvedValue(null); // degraded — inconclusive

    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/deruelle/my-repo" }),
    );
    expect(res.status).toBe(200);
    expect(mockProvisionWorkspaceWithRepo.mock.calls[0][2]).toBe(999);
  });

  test("invalid origin → 403 (CSRF gate preserved)", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: null });
    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(403);
  });

  test("unauthenticated → 401 (auth gate preserved)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(
      makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }),
    );
    expect(res.status).toBe(401);
  });
});
