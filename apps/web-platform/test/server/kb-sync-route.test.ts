// #4224 — manual sync endpoint. `POST /api/kb/sync` resolves the workspace
// SERVER-SIDE from session.user_id (the request body is IGNORED — Sharp Edge
// ownership rule), calls `syncWorkspace`, appends a `{ trigger: "manual" }` row
// to kb_sync_history. Webhook-independent.
//
// #5005 — readiness + path + installation are resolved from the caller's ACTIVE
// workspace via the membership-scoped service-role resolvers
// (`resolveActiveWorkspaceKbRoot` + `resolveActiveWorkspaceRepoMeta`), NOT from
// the caller's own `users` row. The own-row read was the empty solo row for an
// invited member and stale/empty for any account provisioned after the ADR-044
// `users → workspaces` relocation, which 409'd "Sync now" on a connected
// workspace. The legacy 409 client contract (error/code that `KbSyncStatus`
// reads) is preserved.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const {
  mockGetUser,
  mockValidateOrigin,
  mockRejectCsrf,
  mockSyncWorkspace,
  mockAppendKbSyncRow,
  mockReportSilentFallback,
  mockResolveKbRoot,
  mockResolveRepoMeta,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockRejectCsrf: vi.fn(
    () =>
      new Response(JSON.stringify({ error: "CSRF" }), {
        status: 403,
        headers: { "content-type": "application/json" },
      }),
  ),
  mockSyncWorkspace: vi.fn(),
  mockAppendKbSyncRow: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockResolveKbRoot: vi.fn(),
  mockResolveRepoMeta: vi.fn(),
}));

const serviceClientSentinel = { from: vi.fn() };

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
  createServiceClient: () => serviceClientSentinel,
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspaceKbRoot: mockResolveKbRoot,
  resolveActiveWorkspaceRepoMeta: mockResolveRepoMeta,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/server/kb-route-helpers", () => ({
  syncWorkspace: mockSyncWorkspace,
}));

vi.mock("@/server/session-sync", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/session-sync")>();
  return {
    // Preserve real constants (error_class literals, event name, etc.)
    ...actual,
    appendKbSyncRow: mockAppendKbSyncRow,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import { POST } from "@/app/api/kb/sync/route";

const ACTIVE_ID = "active-ws-1";
const ACTIVE_PATH = "/ws/active-ws-1";

function makeRequest(opts: { body?: object } = {}): Request {
  return new Request("https://soleur.ai/api/kb/sync", {
    method: "POST",
    headers: {
      Origin: "https://app.soleur.ai",
      "content-type": "application/json",
    },
    body: JSON.stringify(opts.body ?? {}),
  });
}

// Resolver returns ready + connected by default; per-test overrides exercise the
// gate paths.
function resolverReady() {
  mockResolveKbRoot.mockResolvedValue({
    ok: true,
    activeWorkspaceId: ACTIVE_ID,
    workspacePath: ACTIVE_PATH,
    kbRoot: `${ACTIVE_PATH}/knowledge-base`,
    repoStatus: "ready",
  });
  mockResolveRepoMeta.mockResolvedValue({
    ok: true,
    repoUrl: "https://github.com/owner/repo",
    githubInstallationId: 42,
  });
}

beforeEach(() => {
  mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockSyncWorkspace.mockReset();
  mockAppendKbSyncRow.mockReset();
  mockReportSilentFallback.mockReset();
  mockResolveKbRoot.mockReset();
  mockResolveRepoMeta.mockReset();
  resolverReady();
});

afterEach(() => vi.clearAllMocks());

describe("POST /api/kb/sync — auth gate", () => {
  it("returns 401 when no session user", async () => {
    mockGetUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(401);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
  });
});

describe("POST /api/kb/sync — CSRF gate", () => {
  it("returns 403 when origin invalid", async () => {
    mockValidateOrigin.mockReturnValueOnce({ valid: false, origin: "evil.example" });
    const res = await POST(makeRequest());
    expect(res.status).toBe(403);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
  });
});

describe("POST /api/kb/sync — readiness/connectivity gate (#5005)", () => {
  it("returns 409 WORKSPACE_NOT_READY when the resolver reports not-ready (503)", async () => {
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 503 });

    const res = await POST(makeRequest());
    expect(res.status).toBe(409);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
    const body = await res.json();
    expect(body).toEqual(
      expect.objectContaining({
        error: expect.any(String),
        code: "WORKSPACE_NOT_READY",
      }),
    );
  });

  it("returns 409 Workspace not connected when the resolver reports not-connected (404)", async () => {
    mockResolveKbRoot.mockResolvedValue({ ok: false, status: 404 });

    const res = await POST(makeRequest());
    expect(res.status).toBe(409);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
    const body = await res.json();
    expect(body.error).toBe("Workspace not connected");
  });

  it("returns 409 Workspace not connected when repo-meta resolution fails", async () => {
    mockResolveRepoMeta.mockResolvedValue({ ok: false, status: 400 });

    const res = await POST(makeRequest());
    expect(res.status).toBe(409);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
    const body = await res.json();
    expect(body.error).toBe("Workspace not connected");
  });
});

describe("POST /api/kb/sync — happy path", () => {
  it("calls syncWorkspace + appends manual-trigger row + returns {ok:true,...}", async () => {
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockSyncWorkspace).toHaveBeenCalledTimes(1);
    // Keyed to the resolver's active path + installation id — never the
    // caller's own (possibly empty) users row.
    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      42,
      ACTIVE_PATH,
      expect.anything(),
      expect.objectContaining({ userId: "user-1", op: "manual" }),
    );
    // repo-meta keyed to the already-resolved active id (one membership-resolved id).
    expect(mockResolveRepoMeta).toHaveBeenCalledWith(
      "user-1",
      serviceClientSentinel,
      ACTIVE_ID,
    );
    expect(mockAppendKbSyncRow).toHaveBeenCalledTimes(1);
    expect(mockAppendKbSyncRow).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({ trigger: "manual", ok: true }),
    );

    const body = await res.json();
    expect(body).toEqual(
      expect.objectContaining({ ok: true, at: expect.any(String) }),
    );
  });

  it("syncs successfully for a stale-own-row caller (post-relocation / invited member, #5005)", async () => {
    // The resolver resolves a DIVERGENT active workspace the caller's own users
    // row knows nothing about. Sync must proceed under the resolver's path.
    const DIVERGENT_PATH = "/ws/active-divergent";
    mockResolveKbRoot.mockResolvedValue({
      ok: true,
      activeWorkspaceId: "active-divergent",
      workspacePath: DIVERGENT_PATH,
      kbRoot: `${DIVERGENT_PATH}/knowledge-base`,
      repoStatus: "ready",
    });
    mockResolveRepoMeta.mockResolvedValue({
      ok: true,
      repoUrl: "https://github.com/owner/repo",
      githubInstallationId: 99,
    });
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      99,
      DIVERGENT_PATH,
      expect.anything(),
      expect.objectContaining({ userId: "user-1", op: "manual" }),
    );
  });
});

describe("POST /api/kb/sync — server-side workspace resolution", () => {
  it("IGNORES request body workspace_path — resolves from session.user_id only", async () => {
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    // The attacker passes a different workspace path in the body. The route
    // MUST resolve from session.user_id (via the resolver) only.
    await POST(makeRequest({ body: { workspace_path: "/ws/SOMEONE-ELSE" } }));

    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      42,
      ACTIVE_PATH,
      expect.anything(),
      expect.anything(),
    );
    expect(mockSyncWorkspace).not.toHaveBeenCalledWith(
      expect.anything(),
      "/ws/SOMEONE-ELSE",
      expect.anything(),
      expect.anything(),
    );
  });
});

describe("POST /api/kb/sync — sync failure", () => {
  it("propagates the REAL error_class from syncResult (sync_failed) — not a hard-coded literal", async () => {
    mockSyncWorkspace.mockResolvedValue({
      ok: false,
      error: new Error("auth failed"),
      errorClass: "sync_failed",
    });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockAppendKbSyncRow).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({
        trigger: "manual",
        ok: false,
        error_class: "sync_failed",
      }),
    );
    const body = await res.json();
    expect(body).toEqual(
      expect.objectContaining({ ok: false, error_class: "sync_failed" }),
    );
  });

  it("propagates error_class:non_fast_forward when syncResult classifies a diverged clone (AC-B2)", async () => {
    mockSyncWorkspace.mockResolvedValue({
      ok: false,
      error: new Error("Not possible to fast-forward, aborting."),
      errorClass: "non_fast_forward",
    });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockAppendKbSyncRow).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({
        trigger: "manual",
        ok: false,
        error_class: "non_fast_forward",
      }),
    );
    const body = await res.json();
    expect(body).toEqual(
      expect.objectContaining({ ok: false, error_class: "non_fast_forward" }),
    );
  });

  it("records a recovered:true ok-row when syncWorkspace self-healed (AC-B4)", async () => {
    mockSyncWorkspace.mockResolvedValue({ ok: true, recovered: true });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockAppendKbSyncRow).toHaveBeenCalledWith(
      "user-1",
      expect.objectContaining({ trigger: "manual", ok: true, recovered: true }),
    );
    const body = await res.json();
    expect(body).toEqual(expect.objectContaining({ ok: true, recovered: true }));
  });
});
