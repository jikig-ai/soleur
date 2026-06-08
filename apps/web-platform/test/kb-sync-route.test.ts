/**
 * #5005 — `POST /api/kb/sync` resolver convergence.
 *
 * The route previously resolved readiness + workspace_path + installation from
 * the CALLER's own `users` row via a tenant client. That row is the empty solo
 * row for an invited member, and stale/empty for any account provisioned after
 * the ADR-044 `users → workspaces` relocation — so "Sync now" returned a 409 on
 * a connected workspace. This converges onto the same membership-scoped
 * service-role resolvers the kb/upload route already uses
 * (`resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta`).
 *
 * The existing `kb-sync-status.test.tsx` covers the UI component; this is the
 * route-handler test (the route had none).
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockResolveKbRoot, mockResolveRepoMeta, mockSyncWorkspace, mockAppendRow } =
  vi.hoisted(() => ({
    mockResolveKbRoot: vi.fn(),
    mockResolveRepoMeta: vi.fn(),
    mockSyncWorkspace: vi.fn(),
    mockAppendRow: vi.fn(),
  }));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.test" }),
  rejectCsrf: () =>
    new Response(JSON.stringify({ error: "csrf" }), { status: 403 }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: {
      getUser: vi.fn(async () => ({
        data: { user: { id: "user-123" } },
      })),
    },
  })),
  createServiceClient: vi.fn(() => ({ from: vi.fn() })),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mockResolveKbRoot,
  resolveActiveWorkspaceRepoMeta: mockResolveRepoMeta,
}));

vi.mock("@/server/kb-route-helpers", () => ({
  syncWorkspace: mockSyncWorkspace,
}));

vi.mock("@/server/session-sync", () => ({
  appendKbSyncRow: mockAppendRow,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: {
    error: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
    trace: vi.fn(),
    child: vi.fn().mockReturnThis(),
  },
}));

const WORKSPACE_PATH = "/workspaces/active-ws-999";
const ACTIVE_ID = "active-ws-999";

function makeRequest(): Request {
  return new Request("https://app.test/api/kb/sync", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockAppendRow.mockResolvedValue(undefined);
});

describe("POST /api/kb/sync — resolver convergence (#5005)", () => {
  it("syncs successfully for a post-relocation/invited caller whose own users row is stale", async () => {
    // The caller's own `users.workspace_path`/`workspace_status` are empty, but
    // the resolver resolves the ACTIVE workspace as ready + connected.
    mockResolveKbRoot.mockResolvedValue({
      ok: true,
      activeWorkspaceId: ACTIVE_ID,
      workspacePath: WORKSPACE_PATH,
      kbRoot: `${WORKSPACE_PATH}/knowledge-base`,
      repoStatus: "ready",
    });
    mockResolveRepoMeta.mockResolvedValue({
      ok: true,
      repoUrl: "https://github.com/owner/repo",
      githubInstallationId: 4242,
    });
    mockSyncWorkspace.mockResolvedValue({ ok: true, recovered: false });

    const { POST } = await import("@/app/api/kb/sync/route");
    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    // syncWorkspace is keyed to the resolver's active path + installation id,
    // NOT the caller's own (empty) users row.
    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      4242,
      WORKSPACE_PATH,
      expect.anything(),
      expect.objectContaining({ userId: "user-123", op: "manual" }),
    );
  });

  it("keys repo-meta resolution to the already-resolved active workspace id", async () => {
    mockResolveKbRoot.mockResolvedValue({
      ok: true,
      activeWorkspaceId: ACTIVE_ID,
      workspacePath: WORKSPACE_PATH,
      kbRoot: `${WORKSPACE_PATH}/knowledge-base`,
      repoStatus: "ready",
    });
    mockResolveRepoMeta.mockResolvedValue({
      ok: true,
      repoUrl: "https://github.com/owner/repo",
      githubInstallationId: 4242,
    });
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    const { POST } = await import("@/app/api/kb/sync/route");
    await POST(makeRequest());

    expect(mockResolveRepoMeta).toHaveBeenCalledWith(
      "user-123",
      expect.anything(),
      ACTIVE_ID,
    );
  });

  it("returns 409 WORKSPACE_NOT_READY when the resolver reports not-ready (503)", async () => {
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 503 });

    const { POST } = await import("@/app/api/kb/sync/route");
    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.code).toBe("WORKSPACE_NOT_READY");
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
  });

  it("returns 409 Workspace not connected when the resolver reports not-connected (404)", async () => {
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 404 });

    const { POST } = await import("@/app/api/kb/sync/route");
    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.error).toBe("Workspace not connected");
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
  });

  it("returns 409 Workspace not connected when repo-meta resolution fails", async () => {
    mockResolveKbRoot.mockResolvedValue({
      ok: true,
      activeWorkspaceId: ACTIVE_ID,
      workspacePath: WORKSPACE_PATH,
      kbRoot: `${WORKSPACE_PATH}/knowledge-base`,
      repoStatus: "ready",
    });
    mockResolveRepoMeta.mockResolvedValue({ ok: false, status: 400 });

    const { POST } = await import("@/app/api/kb/sync/route");
    const res = await POST(makeRequest());
    const body = await res.json();

    expect(res.status).toBe(409);
    expect(body.error).toBe("Workspace not connected");
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
  });

  it("returns 401 when unauthenticated", async () => {
    const serverMod = await import("@/lib/supabase/server");
    vi.mocked(serverMod.createClient).mockResolvedValueOnce({
      auth: {
        getUser: vi.fn(async () => ({ data: { user: null } })),
      },
    } as never);

    const { POST } = await import("@/app/api/kb/sync/route");
    const res = await POST(makeRequest());

    expect(res.status).toBe(401);
  });
});
