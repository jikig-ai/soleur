import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks (declared before the route import)
// ---------------------------------------------------------------------------
const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();
const mockValidateOrigin = vi.fn();
const mockProvisionWorkspaceWithRepo = vi.fn();
const mockMirror = vi.fn();
const mockResolveReachable = vi.fn();
const mockResolveOwning = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: mockGetUser } }),
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

vi.mock("@/server/workspace-repo-mirror", () => ({
  mirrorRepoColsToSoloWorkspace: (...a: unknown[]) => mockMirror(...a),
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
let storedInstallationId: number | null = null;

function setupServiceClient() {
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return {
        // .select(...).eq(...).single() — initial read
        select: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                github_installation_id: storedInstallationId,
                email: "user@example.com",
                github_username: "deruelle",
              },
              error: null,
            }),
          }),
        }),
        // .update(...).eq(...).neq(...).select(...).maybeSingle() — clone lock
        // .update(...).eq(...).then(...) — error path
        update: () => {
          const chain: Record<string, unknown> = {
            eq: () => chain,
            neq: () => chain,
            select: () => chain,
            maybeSingle: async () => ({ data: { id: "user-1" }, error: null }),
            then: (resolve: (v: { error: null }) => void) =>
              resolve({ error: null }),
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
    setupServiceClient();
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
    // provisionWorkspaceWithRepo(userId, repoUrl, installationId, ...)
    expect(mockProvisionWorkspaceWithRepo.mock.calls[0][2]).toBe(122213433);
  });

  test("T10: membership-fallback path mirrors the RESOLVED install (never a users.update of github_installation_id)", async () => {
    storedInstallationId = null;
    mockResolveReachable.mockResolvedValue([122213433]);
    mockResolveOwning.mockResolvedValue(122213433);

    await POST(makeRequest({ repoUrl: "https://github.com/jikig-ai/soleur" }));

    // Mirror to the solo WORKSPACE may carry the install (ADR-044 — allowed).
    // The install written is the RESOLVED id, never persisted to users.
    const mirrorInstallWrites = mockMirror.mock.calls.filter(
      (c) =>
        (c[2] as { github_installation_id?: number }).github_installation_id !=
        null,
    );
    expect(mirrorInstallWrites.length).toBeGreaterThan(0);
    for (const c of mirrorInstallWrites) {
      expect(
        (c[2] as { github_installation_id: number }).github_installation_id,
      ).toBe(122213433);
    }
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

  test("T13: degraded probe (owning null) but stored id present → falls back to stored id", async () => {
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
