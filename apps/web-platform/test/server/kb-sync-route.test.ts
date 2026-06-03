// #4224 — manual sync endpoint. `POST /api/kb/sync` resolves
// workspace_path SERVER-SIDE from session.user_id (the request body is
// IGNORED — Sharp Edge ownership rule), calls `syncWorkspace`, appends
// a `{ trigger: "manual" }` row to kb_sync_history. Webhook-independent.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const {
  mockGetUser,
  mockValidateOrigin,
  mockRejectCsrf,
  mockSyncWorkspace,
  mockAppendKbSyncRow,
  mockReportSilentFallback,
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
}));

// Per-test fixture rows for the user table. Mock returns single() / maybeSingle()
// from the seeded row keyed by user-id.
const USER_ROWS = new Map<
  string,
  {
    workspace_path: string | null;
    workspace_status: string | null;
    github_installation_id: number | null;
  }
>();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async (userId: string) => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          single: async () => {
            const row = USER_ROWS.get(userId);
            if (!row) return { data: null, error: { code: "PGRST116" } };
            return { data: row, error: null };
          },
        }),
      }),
    }),
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
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

beforeEach(() => {
  USER_ROWS.clear();
  mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockSyncWorkspace.mockReset();
  mockAppendKbSyncRow.mockReset();
  mockReportSilentFallback.mockReset();
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

describe("POST /api/kb/sync — workspace_status gate", () => {
  it("returns 409 when workspace_status != ready", async () => {
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/user-1",
      workspace_status: "cloning",
      github_installation_id: 42,
    });

    const res = await POST(makeRequest());
    expect(res.status).toBe(409);
    expect(mockSyncWorkspace).not.toHaveBeenCalled();
    const body = await res.json();
    expect(body).toEqual(
      expect.objectContaining({ error: expect.any(String) }),
    );
  });
});

describe("POST /api/kb/sync — happy path", () => {
  it("calls syncWorkspace + appends manual-trigger row + returns {ok:true,...}", async () => {
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/user-1",
      workspace_status: "ready",
      github_installation_id: 42,
    });
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockSyncWorkspace).toHaveBeenCalledTimes(1);
    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      42,
      "/ws/user-1",
      expect.anything(),
      expect.objectContaining({ userId: "user-1", op: "manual" }),
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
});

describe("POST /api/kb/sync — server-side workspace_path resolution", () => {
  it("IGNORES request body workspace_path — uses session.user_id only", async () => {
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/legit-user-1",
      workspace_status: "ready",
      github_installation_id: 42,
    });
    mockSyncWorkspace.mockResolvedValue({ ok: true });

    // The attacker passes a different workspace path in the body. The
    // route MUST resolve from session.user_id only.
    await POST(
      makeRequest({ body: { workspace_path: "/ws/SOMEONE-ELSE" } }),
    );

    expect(mockSyncWorkspace).toHaveBeenCalledWith(
      42,
      "/ws/legit-user-1",
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
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/user-1",
      workspace_status: "ready",
      github_installation_id: 42,
    });
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
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/user-1",
      workspace_status: "ready",
      github_installation_id: 42,
    });
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
    USER_ROWS.set("user-1", {
      workspace_path: "/ws/user-1",
      workspace_status: "ready",
      github_installation_id: 42,
    });
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
