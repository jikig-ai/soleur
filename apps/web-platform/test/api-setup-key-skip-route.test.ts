import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-skip-api-key-onboarding (#4642) — AC4. POST /api/setup-key/skip:
//  - CSRF-guarded (validateOrigin / rejectCsrf), mirrors accept-terms.
//  - authed; userId strictly from supabase.auth.getUser().
//  - service-client UPDATE users SET setup_key_skipped_at = now() WHERE id =
//    user.id, asserting EXACTLY 1 affected row (≠1 → 500 + Sentry mirror).
//    Client-side updateUserField would silently no-op (mig 006 REVOKE).

const {
  mockGetUser,
  mockServiceUpdate,
  mockServiceEq,
  mockServiceSelect,
  mockReportSilentFallback,
  mockValidateOrigin,
  mockRejectCsrf,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceUpdate: vi.fn(),
  mockServiceEq: vi.fn(),
  mockServiceSelect: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({
    from: () => ({
      update: mockServiceUpdate.mockReturnValue({
        eq: mockServiceEq.mockReturnValue({ select: mockServiceSelect }),
      }),
    }),
  })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
  captureException: vi.fn(),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => `hash:${id}`,
}));

import { POST } from "@/app/api/setup-key/skip/route";

const USER_ID = "user-skip-uuid";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/setup-key/skip", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai" },
  });
}

function setupAuthedUser(): void {
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID, email: "u@x.com" } } });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(
    new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  );
  // Default: update affects exactly one row.
  mockServiceSelect.mockResolvedValue({ data: [{ id: USER_ID }], error: null });
});

describe("POST /api/setup-key/skip (AC4)", () => {
  test("403 on CSRF origin failure (no write)", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil" });
    const res = await POST(makeRequest());
    expect(res.status).toBe(403);
    expect(mockServiceUpdate).not.toHaveBeenCalled();
  });

  test("401 when unauthenticated (no write)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(401);
    expect(mockServiceUpdate).not.toHaveBeenCalled();
  });

  test("persists setup_key_skipped_at (non-null timestamp) scoped to the user and returns ok", async () => {
    setupAuthedUser();
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    // The update payload sets the skip timestamp...
    const payload = mockServiceUpdate.mock.calls[0][0] as { setup_key_skipped_at: unknown };
    expect(payload.setup_key_skipped_at).toBeTruthy();
    // ...scoped to the authenticated user's own row.
    expect(mockServiceEq).toHaveBeenCalledWith("id", USER_ID);
  });

  test("500 + Sentry mirror when update affects 0 rows", async () => {
    setupAuthedUser();
    mockServiceSelect.mockResolvedValue({ data: [], error: null });
    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("500 + Sentry mirror on update error", async () => {
    setupAuthedUser();
    mockServiceSelect.mockResolvedValue({ data: null, error: { message: "db boom" } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
