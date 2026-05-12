import { describe, it, expect, beforeEach, vi } from "vitest";

// Route tests for app/api/account/export/* — Phase 6.
//
// Per plan rev-2 FR3 + FR5 + AC4 + AC5 + AC16 + AC20 + AC24.
//
// Each test mocks the supabase client surface the route consumes so
// we exercise the route's branching (CSRF, auth, rate-limit, reauth,
// lifecycle gates) without a live Supabase. Cross-tenant correctness
// is covered separately by dsar-export-cross-tenant.integration.test.ts
// (Phase 10).

const hoisted = vi.hoisted(() => ({
  getUserMock: vi.fn(),
  getSessionMock: vi.fn(),
  fromMock: vi.fn(),
  rpcMock: vi.fn(),
  storageMock: vi.fn(),
  enqueueExportMock: vi.fn(),
  requireFreshReauthMock: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: {
      getUser: hoisted.getUserMock,
      getSession: hoisted.getSessionMock,
    },
    from: hoisted.fromMock,
  })),
  // createServiceClient is re-exported from server; tests stub the
  // service path below.
  createServiceClient: vi.fn(() => ({
    from: hoisted.fromMock,
    rpc: hoisted.rpcMock,
    storage: hoisted.storageMock(),
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    from: hoisted.fromMock,
    rpc: hoisted.rpcMock,
    storage: hoisted.storageMock(),
  })),
  serverUrl: () => "https://test.supabase.co",
}));

vi.mock("@/server/dsar-export", () => ({
  enqueueExport: hoisted.enqueueExportMock,
}));

vi.mock("@/server/dsar-reauth", async () => {
  const actual = await vi.importActual<typeof import("../server/dsar-reauth")>(
    "../server/dsar-reauth",
  );
  return {
    ...actual,
    requireFreshReauth: hoisted.requireFreshReauthMock,
  };
});

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { POST as postExport } from "../app/api/account/export/route";
import { GET as getDownload } from "../app/api/account/export/[jobId]/download/route";

// Each test uses a unique user id so the module-scoped
// SlidingWindowCounter in route.ts does not leak slot-burn state
// between tests (the limiter window is 60s; we don't want to mock
// time globally).
const userIdSeq = (() => {
  let n = 0;
  return () => {
    n++;
    return `aaaaaaaa-aaaa-aaaa-aaaa-${String(n).padStart(12, "0")}`;
  };
})();
const USER_ID = "11111111-1111-1111-1111-111111111111";
const SESSION_ID = "22222222-2222-2222-2222-222222222222";
const JOB_ID = "33333333-3333-3333-3333-333333333333";

function makeRequest(
  method: "POST" | "GET",
  path: string,
  init: { headers?: Record<string, string>; body?: unknown } = {},
): Request {
  const url = `https://app.soleur.ai${path}`;
  return new Request(url, {
    method,
    headers: {
      origin: "https://app.soleur.ai",
      ...(init.headers ?? {}),
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  hoisted.storageMock.mockReturnValue({
    from: () => ({
      remove: vi.fn().mockResolvedValue({ data: null, error: null }),
    }),
  });
});

describe("POST /api/account/export — CSRF + auth + rate-limit", () => {
  it("rejects mismatched Origin with 403", async () => {
    const req = new Request("https://app.soleur.ai/api/account/export", {
      method: "POST",
      headers: { origin: "https://evil.example" },
    });
    const res = await postExport(req);
    expect(res.status).toBe(403);
  });

  it("rejects unauthenticated callers with 401", async () => {
    hoisted.getUserMock.mockResolvedValue({ data: null, error: null });
    const req = makeRequest("POST", "/api/account/export");
    const res = await postExport(req);
    expect(res.status).toBe(401);
  });

  it("rejects missing reauth event with 401 (not_found reason)", async () => {
    hoisted.getUserMock.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });
    hoisted.getSessionMock.mockResolvedValue({ data: { session: null } });
    const { ReauthEventInvalid } = await import("../server/dsar-reauth");
    hoisted.requireFreshReauthMock.mockRejectedValue(
      new ReauthEventInvalid("not_found"),
    );
    const req = makeRequest("POST", "/api/account/export", {
      headers: { "x-forwarded-for": "1.2.3.4" },
    });
    const res = await postExport(req);
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.reason).toBe("not_found");
  });

  it("returns 403 on session_mismatch (attacker holds eventId but not session)", async () => {
    const uid = userIdSeq();
    hoisted.getUserMock.mockResolvedValue({
      data: { user: { id: uid } },
      error: null,
    });
    const { ReauthEventInvalid } = await import("../server/dsar-reauth");
    hoisted.requireFreshReauthMock.mockRejectedValue(
      new ReauthEventInvalid("session_mismatch"),
    );
    const req = makeRequest("POST", "/api/account/export", {
      headers: { "x-reauth-event": "ev-1" },
    });
    const res = await postExport(req);
    expect(res.status).toBe(403);
  });

  it("returns 202 with job_id + acknowledged_at on success", async () => {
    const uid = userIdSeq();
    hoisted.getUserMock.mockResolvedValue({
      data: { user: { id: uid } },
      error: null,
    });
    hoisted.getSessionMock.mockResolvedValue({
      data: { session: { session_id: SESSION_ID } },
    });
    hoisted.requireFreshReauthMock.mockResolvedValue({
      userId: uid,
      sessionId: SESSION_ID,
    });
    hoisted.enqueueExportMock.mockResolvedValue({
      jobId: JOB_ID,
      acknowledgedAt: "2026-05-12T10:00:00Z",
    });
    const req = makeRequest("POST", "/api/account/export", {
      headers: { "x-reauth-event": "ev-1" },
    });
    const res = await postExport(req);
    expect(res.status).toBe(202);
    const body = await res.json();
    expect(body.job_id).toBe(JOB_ID);
    expect(body.acknowledged_at).toBe("2026-05-12T10:00:00Z");
  });

  it("returns 429 when the user retries within 60 seconds", async () => {
    const uid = userIdSeq();
    hoisted.getUserMock.mockResolvedValue({
      data: { user: { id: uid } },
      error: null,
    });
    hoisted.getSessionMock.mockResolvedValue({
      data: { session: { session_id: SESSION_ID } },
    });
    hoisted.requireFreshReauthMock.mockResolvedValue({
      userId: uid,
      sessionId: SESSION_ID,
    });
    hoisted.enqueueExportMock.mockResolvedValue({
      jobId: JOB_ID,
      acknowledgedAt: "2026-05-12T10:00:00Z",
    });
    // First call burns the rate-limit slot for this user id.
    await postExport(
      makeRequest("POST", "/api/account/export", {
        headers: { "x-reauth-event": "ev-1" },
      }),
    );
    // Second call from the same user within 60s is 429.
    const res = await postExport(
      makeRequest("POST", "/api/account/export", {
        headers: { "x-reauth-event": "ev-2" },
      }),
    );
    expect(res.status).toBe(429);
  });
});

describe("GET /api/account/export/[jobId]/download — lifecycle gates", () => {
  function setUserAndSession() {
    hoisted.getUserMock.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });
    hoisted.getSessionMock.mockResolvedValue({
      data: { session: { session_id: SESSION_ID } },
    });
  }

  function mockFromJob(jobRow: Record<string, unknown> | null) {
    hoisted.fromMock.mockImplementation((tableName: string) => {
      if (tableName === "dsar_export_jobs") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: async () => ({ data: jobRow, error: null }),
              }),
            }),
          }),
          update: () => ({
            eq: () => ({
              eq: () => ({
                select: () => ({
                  maybeSingle: async () => ({ data: jobRow, error: null }),
                }),
              }),
            }),
          }),
        };
      }
      if (tableName === "dsar_export_audit_pii") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                order: () => ({
                  limit: async () => ({ data: [], error: null }),
                }),
              }),
            }),
          }),
        };
      }
      throw new Error(`Unexpected from(${tableName})`);
    });
  }

  it("returns 401 when unauthenticated", async () => {
    hoisted.getUserMock.mockResolvedValue({ data: null, error: null });
    const res = await getDownload(
      makeRequest("GET", `/api/account/export/${JOB_ID}/download`),
      { params: Promise.resolve({ jobId: JOB_ID }) },
    );
    expect(res.status).toBe(401);
  });

  it("returns 410 Gone for non-existent job (unknown jobId)", async () => {
    setUserAndSession();
    mockFromJob(null);
    const res = await getDownload(
      makeRequest("GET", `/api/account/export/${JOB_ID}/download`),
      { params: Promise.resolve({ jobId: JOB_ID }) },
    );
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.error).toBe("export_expired");
  });

  it("returns 410 Gone when job status is `expired`", async () => {
    setUserAndSession();
    mockFromJob({
      id: JOB_ID,
      user_id: USER_ID,
      status: "expired",
      owner_session_id: SESSION_ID,
      signed_url_expires_at: new Date(Date.now() + 60_000).toISOString(),
    });
    const res = await getDownload(
      makeRequest("GET", `/api/account/export/${JOB_ID}/download`),
      { params: Promise.resolve({ jobId: JOB_ID }) },
    );
    expect(res.status).toBe(410);
  });

  it("returns 410 Gone when signed_url_expires_at is in the past", async () => {
    setUserAndSession();
    mockFromJob({
      id: JOB_ID,
      user_id: USER_ID,
      status: "completed",
      owner_session_id: SESSION_ID,
      signed_url_expires_at: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await getDownload(
      makeRequest("GET", `/api/account/export/${JOB_ID}/download`),
      { params: Promise.resolve({ jobId: JOB_ID }) },
    );
    expect(res.status).toBe(410);
  });

  it("returns 409 session_mismatch when owner_session_id differs", async () => {
    setUserAndSession();
    mockFromJob({
      id: JOB_ID,
      user_id: USER_ID,
      status: "completed",
      owner_session_id: "other-session",
      signed_url_expires_at: new Date(Date.now() + 60_000).toISOString(),
    });
    const res = await getDownload(
      makeRequest("GET", `/api/account/export/${JOB_ID}/download`),
      { params: Promise.resolve({ jobId: JOB_ID }) },
    );
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error).toBe("session_mismatch");
  });
});
