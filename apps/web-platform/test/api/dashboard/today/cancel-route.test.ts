/**
 * PR-B (#4379) AC13 — POST /api/dashboard/today/[id]/cancel
 *
 * Covers happy path, owner-mismatch 403, missing-session 401, double-
 * click idempotency, and CSRF rejection.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const {
  mockGetUser,
  mockTenantFrom,
  mockServiceFrom,
  mockValidateOrigin,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockTenantFrom: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({
    valid: true,
    origin: "https://app.soleur.ai",
  })),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockTenantFrom,
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

const FOUNDER_ID = "founder-123";
const MESSAGE_ID = "msg-001";

interface TenantOwnerCheckResult {
  found: boolean;
  err?: unknown;
}

function setupTenantChain(result: TenantOwnerCheckResult) {
  const chain = {
    from: vi.fn((_t?: string) => chain),
    select: vi.fn((_c?: string) => chain),
    eq: vi.fn((_c?: string, _v?: unknown) => chain),
    maybeSingle: vi.fn(async () => ({
      data: result.found ? { id: MESSAGE_ID } : null,
      error: result.err ?? null,
    })),
  };
  (mockTenantFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => chain.from(table));
  return chain;
}

function setupServiceChain(result: { updateError?: unknown }) {
  const captured = {
    patches: [] as Array<{ table: string; patch: unknown; eqArgs: unknown[] }>,
  };
  const chain = {
    table: "",
    patch: undefined as unknown,
    eqArgs: [] as unknown[],
    from(table: string) {
      this.table = table;
      this.patch = undefined;
      this.eqArgs = [];
      return chain;
    },
    update(patch: unknown) {
      this.patch = patch;
      return chain;
    },
    eq(col: string, val: unknown) {
      this.eqArgs.push({ col, val });
      // terminal for update path
      captured.patches.push({
        table: this.table,
        patch: this.patch,
        eqArgs: [...this.eqArgs],
      });
      return Promise.resolve({ error: result.updateError ?? null });
    },
  };
  (mockServiceFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => chain.from(table));
  return captured;
}

function makeRequest() {
  return new Request("https://app.soleur.ai/api/dashboard/today/msg-001/cancel", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
  });
}

const paramsPromise = Promise.resolve({ id: MESSAGE_ID });

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_ID } } });
  mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  });
});

describe("POST /api/dashboard/today/[id]/cancel", () => {
  test("happy path: writes cancellation_requested_at via service-role", async () => {
    setupTenantChain({ found: true });
    const captured = setupServiceChain({});
    const { POST } = await import(
      "@/app/api/dashboard/today/[id]/cancel/route"
    );
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean };
    expect(body.ok).toBe(true);
    expect(captured.patches).toHaveLength(1);
    const update = captured.patches[0];
    expect(update.table).toBe("action_sends");
    const patch = update.patch as Record<string, unknown>;
    expect(typeof patch.cancellation_requested_at).toBe("string");
    expect(update.eqArgs).toEqual([{ col: "message_id", val: MESSAGE_ID }]);
  });

  test("owner-mismatch → 403", async () => {
    setupTenantChain({ found: false });
    setupServiceChain({});
    const { POST } = await import(
      "@/app/api/dashboard/today/[id]/cancel/route"
    );
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
  });

  test("no auth session → 401", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    setupTenantChain({ found: true });
    const { POST } = await import(
      "@/app/api/dashboard/today/[id]/cancel/route"
    );
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(401);
  });

  test("double-click is idempotent (200 on second call)", async () => {
    setupTenantChain({ found: true });
    const captured = setupServiceChain({});
    const { POST } = await import(
      "@/app/api/dashboard/today/[id]/cancel/route"
    );
    const r1 = await POST(makeRequest(), { params: paramsPromise });
    const r2 = await POST(makeRequest(), { params: paramsPromise });
    expect(r1.status).toBe(200);
    expect(r2.status).toBe(200);
    expect(captured.patches).toHaveLength(2);
  });

  test("CSRF rejection → 403 (validateOrigin returns valid:false)", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "evil.example" });
    const { POST } = await import(
      "@/app/api/dashboard/today/[id]/cancel/route"
    );
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
  });
});
