import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Hoisted mocks — vi.mock is hoisted above imports, so shared refs must use
// vi.hoisted() to be available inside mock factories.
// ---------------------------------------------------------------------------

const {
  mockScanProjectHealth,
  mockProvisionWorkspaceWithRepo,
  mockSupabaseUpdate,
  mockSupabaseUserUpdate,
  mockSupabaseEq,
  mockSupabaseNeq,
  mockSupabaseSelect,
  mockSupabaseMaybeSingle,
  mockSupabaseInsert,
  mockUserHasEffectiveByokKey,
} = vi.hoisted(() => {
  const mockSupabaseEq = vi.fn();
  const mockSupabaseNeq = vi.fn();
  const mockSupabaseSelect = vi.fn();
  const mockSupabaseMaybeSingle = vi.fn();
  const mockSupabaseInsert = vi.fn();
  // ADR-044 PR-2: the workspaces cloning-flip lock update.
  const mockSupabaseUpdate = vi.fn();
  // The solo readiness write on `users`: .update({...}).eq("id", user.id).
  const mockSupabaseUserUpdate = vi.fn();

  // workspaces lock chain: .update().eq().neq().select().maybeSingle()
  mockSupabaseMaybeSingle.mockResolvedValue({
    data: { id: "user-123" },
    error: null,
  });
  mockSupabaseSelect.mockReturnValue({ maybeSingle: mockSupabaseMaybeSingle });
  mockSupabaseNeq.mockReturnValue({ select: mockSupabaseSelect });
  mockSupabaseEq.mockReturnValue({ neq: mockSupabaseNeq });
  mockSupabaseUpdate.mockReturnValue({ eq: mockSupabaseEq });
  // users readiness chain: .update().eq() → { error: null }
  mockSupabaseUserUpdate.mockReturnValue({
    eq: vi.fn().mockResolvedValue({ error: null }),
  });
  mockSupabaseInsert.mockResolvedValue({ error: null });

  return {
    mockScanProjectHealth: vi.fn().mockReturnValue({
      scannedAt: new Date().toISOString(),
      category: "developing",
      signals: { detected: [], missing: [] },
      recommendations: [],
      kbExists: false,
    }),
    mockProvisionWorkspaceWithRepo: vi.fn().mockResolvedValue("/tmp/workspace"),
    mockSupabaseUpdate,
    mockSupabaseUserUpdate,
    mockSupabaseEq,
    mockSupabaseNeq,
    mockSupabaseSelect,
    mockSupabaseMaybeSingle,
    mockSupabaseInsert,
    mockUserHasEffectiveByokKey: vi.fn().mockResolvedValue(true),
  };
});

vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
}));

// ADR-044 PR-2: the active workspace id is resolved server-side via the
// membership-verified resolver. Default to SOLO (== user-123) so these
// health-scanner tests exercise the solo readiness-write split. The team /
// db-error branches are covered in the install-resolution suite.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: vi.fn(async (userId: string) => ({
    ok: true,
    workspaceId: userId,
  })),
  resolveCurrentWorkspaceId: vi.fn(async (userId: string) => userId),
}));

// ADR-044 PR-2: the authoritative repo-connection write now targets the
// `workspaces` row via writeRepoColsToWorkspace (was the solo-`users` mirror).
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: vi.fn(async () => {}),
}));

// ---------------------------------------------------------------------------
// Module mocks
// ---------------------------------------------------------------------------

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn().mockResolvedValue({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: {
          user: {
            id: "user-123",
            email: "test@example.com",
            user_metadata: { full_name: "Test User" },
          },
        },
      }),
    },
    // ADR-044 owner-gate: default to owner.
    rpc: vi.fn().mockResolvedValue({ data: true, error: null }),
  }),
  createServiceClient: vi.fn().mockReturnValue({
    from: vi.fn((table: string) => {
      if (table === "conversations") {
        return { insert: mockSupabaseInsert };
      }
      if (table === "workspaces") {
        // ADR-044 PR-2: the degraded install fallback reads
        // workspaces.select(github_installation_id).eq(id).maybeSingle(); the
        // cloning-flip lock is .update().eq().neq().select().maybeSingle().
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockReturnValue({
              maybeSingle: vi
                .fn()
                .mockResolvedValue({
                  data: { github_installation_id: 42 },
                  error: null,
                }),
            }),
          }),
          update: mockSupabaseUpdate,
        };
      }
      // "users" table — ADR-044 PR-2 reads only email + github_username; the
      // solo readiness write (.update({workspace_status, health_snapshot}))
      // still targets users.
      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            single: vi.fn().mockResolvedValue({
              data: { email: "test@example.com", github_username: "tester" },
              error: null,
            }),
          }),
        }),
        update: mockSupabaseUserUpdate,
      };
    }),
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn().mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  }),
  rejectCsrf: vi.fn(),
}));

vi.mock("@/server/workspace", () => ({
  provisionWorkspaceWithRepo: mockProvisionWorkspaceWithRepo,
}));

vi.mock("@/server/project-scanner", () => ({
  scanProjectHealth: mockScanProjectHealth,
}));

// The route's fire-and-forget auto-sync (triggerHeadlessSync) lazy-imports
// @/server/agent-runner (the heavy @anthropic-ai/claude-agent-sdk graph). Stub
// it so the keyed-user path's startAgentSession resolves cleanly instead of
// throwing a VitestMocker error from the real SDK import — which would escape
// the fire-and-forget chain as an unhandled post-test rejection (vitest fails
// the run on unhandled errors even when every test passes).
vi.mock("@/server/agent-runner", () => ({
  startAgentSession: vi.fn(async () => {}),
}));

vi.mock("@/server/logger", () => {
  const noopLogger = {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
    child: vi.fn(),
  };
  noopLogger.child.mockReturnValue(noopLogger);
  return {
    default: noopLogger,
    createChildLogger: vi.fn().mockReturnValue(noopLogger),
  };
});

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

vi.mock("next/server", () => ({
  NextResponse: {
    json: (body: unknown, init?: { status?: number }) =>
      new Response(JSON.stringify(body), {
        status: init?.status ?? 200,
        headers: { "content-type": "application/json" },
      }),
  },
}));

// ---------------------------------------------------------------------------
// Import the route handler AFTER all mocks are set up
// ---------------------------------------------------------------------------

import { POST } from "../app/api/repo/setup/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(body: Record<string, unknown>) {
  return new Request("https://app.soleur.ai/api/repo/setup", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
}

/** Flush the microtask queue so the fire-and-forget .then() handler runs. */
async function flushPromises() {
  // Multiple rounds to handle nested .then() chains
  for (let i = 0; i < 10; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("setup route — health scanner guard", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Reset the workspaces optimistic-lock chain:
    // .update().eq().neq().select().maybeSingle()
    mockSupabaseMaybeSingle.mockResolvedValue({
      data: { id: "user-123" },
      error: null,
    });
    mockSupabaseSelect.mockReturnValue({
      maybeSingle: mockSupabaseMaybeSingle,
    });
    mockSupabaseNeq.mockReturnValue({ select: mockSupabaseSelect });
    mockSupabaseEq.mockReturnValue({ neq: mockSupabaseNeq });
    mockSupabaseUpdate.mockReturnValue({ eq: mockSupabaseEq });

    // Reset the solo readiness write on `users`: .update().eq() → { error: null }
    mockSupabaseUserUpdate.mockReturnValue({
      eq: vi.fn().mockResolvedValue({ error: null }),
    });

    // Reset provision mock
    mockProvisionWorkspaceWithRepo.mockResolvedValue("/tmp/workspace");

    // Reset scanner mock
    mockScanProjectHealth.mockReturnValue({
      scannedAt: new Date().toISOString(),
      category: "developing",
      signals: { detected: [], missing: [] },
      recommendations: [],
      kbExists: false,
    });

    // Default: user has a usable key → auto-sync proceeds.
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
  });

  // feat-skip-api-key-onboarding (#4642 review): the auto-sync agent run
  // rejects at getUserApiKey enforcement for a keyless user, which would
  // orphan a stalled "active" conversation behind a "ready" screen. Gate the
  // conversation insert + sync trigger on an effective key (fail-open).
  test("keyless user → no orphaned sync conversation is created", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);

    const response = await POST(
      makeRequest({ repoUrl: "https://github.com/test/repo", source: "connect_existing" }),
    );
    expect(response.status).toBe(200);
    await flushPromises();

    expect(mockUserHasEffectiveByokKey).toHaveBeenCalledWith(
      "user-123",
      expect.objectContaining({ onErrorReturn: true }),
    );
    expect(mockSupabaseInsert).not.toHaveBeenCalled();
  });

  test("user with an effective key → sync conversation IS created", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);

    const response = await POST(
      makeRequest({ repoUrl: "https://github.com/test/repo", source: "connect_existing" }),
    );
    expect(response.status).toBe(200);
    await flushPromises();

    expect(mockSupabaseInsert).toHaveBeenCalled();
  });

  test('does NOT call scanProjectHealth when source is "start_fresh"', async () => {
    const request = makeRequest({
      repoUrl: "https://github.com/test/repo",
      source: "start_fresh",
    });

    const response = await POST(request);
    expect(response.status).toBe(200);

    // Wait for fire-and-forget .then() to execute
    await flushPromises();

    expect(mockScanProjectHealth).not.toHaveBeenCalled();
  });

  test('calls scanProjectHealth when source is "connect_existing"', async () => {
    const request = makeRequest({
      repoUrl: "https://github.com/test/repo",
      source: "connect_existing",
    });

    const response = await POST(request);
    expect(response.status).toBe(200);

    await flushPromises();

    expect(mockScanProjectHealth).toHaveBeenCalledWith("/tmp/workspace");
  });

  test("calls scanProjectHealth when source field is missing (backward compatible)", async () => {
    const request = makeRequest({
      repoUrl: "https://github.com/test/repo",
    });

    const response = await POST(request);
    expect(response.status).toBe(200);

    await flushPromises();

    expect(mockScanProjectHealth).toHaveBeenCalledWith("/tmp/workspace");
  });
});
