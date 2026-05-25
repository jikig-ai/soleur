/**
 * PR-B (#4379) AC15 — GET /api/dashboard/today/[id]/cost
 *
 * Covers: happy path (cumulative sum + turnCount), owner-mismatch 403,
 * 401, agentRole shape, time-window predicate (gt created_at, lte
 * acknowledged_at or now()).
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockGetUser, mockTenantFrom, mockServiceFrom, mockValidateOrigin } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockTenantFrom: vi.fn(),
    mockServiceFrom: vi.fn(),
    mockValidateOrigin: vi.fn(() => ({
      valid: true,
      origin: "https://app.soleur.ai",
    })),
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
  reportSilentFallback: vi.fn(),
}));

const FOUNDER_ID = "founder-123";
const MESSAGE_ID = "msg-001";

function setupTenantChain(found: boolean) {
  const chain = {
    from: vi.fn((_t?: string) => chain),
    select: vi.fn((_c?: string) => chain),
    eq: vi.fn((_c?: string, _v?: unknown) => chain),
    maybeSingle: vi.fn(async () => ({
      data: found ? { id: MESSAGE_ID } : null,
      error: null,
    })),
  };
  (mockTenantFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => chain.from(table));
}

interface AuditQuery {
  agentRole?: unknown;
  founderId?: unknown;
  gtCreatedAt?: unknown;
  lteCreatedAt?: unknown;
}

function setupServiceChain(args: {
  actionSend: {
    id: string;
    user_id: string;
    action_class: string;
    created_at: string;
    acknowledged_at: string | null;
    message_id?: string;
  } | null;
  auditRows: { unit_cost_cents: number }[];
}) {
  const captured: { audit: AuditQuery } = { audit: {} };

  const sendChain = {
    select: vi.fn(() => sendChain),
    eq: vi.fn(() => sendChain),
    maybeSingle: vi.fn(async () => ({
      data: args.actionSend,
      error: null,
    })),
  };
  const auditChain = {
    select: vi.fn(() => auditChain),
    eq: vi.fn((col: string, val: unknown) => {
      if (col === "agent_role") captured.audit.agentRole = val;
      if (col === "founder_id") captured.audit.founderId = val;
      return auditChain;
    }),
    gt: vi.fn((col: string, val: unknown) => {
      if (col === "created_at") captured.audit.gtCreatedAt = val;
      return auditChain;
    }),
    lte: vi.fn((col: string, val: unknown) => {
      if (col === "created_at") captured.audit.lteCreatedAt = val;
      return Promise.resolve({ data: args.auditRows, error: null });
    }),
  };
  (mockServiceFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => {
    if (table === "action_sends") return sendChain;
    if (table === "audit_byok_use") return auditChain;
    throw new Error(`unexpected service-role table ${table}`);
  });
  return captured;
}

function makeRequest() {
  return new Request("https://app.soleur.ai/api/dashboard/today/msg-001/cost", {
    method: "GET",
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

describe("GET /api/dashboard/today/[id]/cost", () => {
  test("happy path: returns cumulativeCents + turnCount; agentRole is action.spawn.requested:<class>", async () => {
    setupTenantChain(true);
    const captured = setupServiceChain({
      actionSend: {
        id: "as-1",
        user_id: FOUNDER_ID,
        action_class: "engineering.pr_review_pending",
        created_at: "2026-05-25T12:00:00Z",
        acknowledged_at: "2026-05-25T12:05:00Z",
        message_id: MESSAGE_ID,
      },
      auditRows: [{ unit_cost_cents: 12 }, { unit_cost_cents: 34 }],
    });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      cumulativeCents: number;
      turnCount: number;
    };
    expect(body).toEqual({ cumulativeCents: 46, turnCount: 2 });
    expect(captured.audit.agentRole).toBe(
      "agent.spawn.requested:engineering.pr_review_pending",
    );
    expect(captured.audit.founderId).toBe(FOUNDER_ID);
    expect(captured.audit.gtCreatedAt).toBe("2026-05-25T12:00:00Z");
    expect(captured.audit.lteCreatedAt).toBe("2026-05-25T12:05:00Z");
  });

  test("no acknowledged_at yet → lte upper bound is `now()` (any ISO string)", async () => {
    setupTenantChain(true);
    const captured = setupServiceChain({
      actionSend: {
        id: "as-2",
        user_id: FOUNDER_ID,
        action_class: "triage.p0p1_issue",
        created_at: "2026-05-25T12:00:00Z",
        acknowledged_at: null,
        message_id: MESSAGE_ID,
      },
      auditRows: [],
    });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    expect(typeof captured.audit.lteCreatedAt).toBe("string");
    expect((captured.audit.lteCreatedAt as string).length).toBeGreaterThan(10);
  });

  test("owner mismatch on messages → 403", async () => {
    setupTenantChain(false);
    setupServiceChain({ actionSend: null, auditRows: [] });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
  });

  test("defense-in-depth: action_sends.user_id mismatch → 403", async () => {
    setupTenantChain(true);
    setupServiceChain({
      actionSend: {
        id: "as-x",
        user_id: "different-founder",
        action_class: "engineering.pr_review_pending",
        created_at: "2026-05-25T12:00:00Z",
        acknowledged_at: null,
        message_id: MESSAGE_ID,
      },
      auditRows: [],
    });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
  });

  test("action_sends row missing → returns 0/0 (in-flight, pre-loop write)", async () => {
    setupTenantChain(true);
    setupServiceChain({ actionSend: null, auditRows: [] });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      cumulativeCents: number;
      turnCount: number;
    };
    expect(body).toEqual({ cumulativeCents: 0, turnCount: 0 });
  });

  test("no auth → 401", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const { GET } = await import("@/app/api/dashboard/today/[id]/cost/route");
    const res = await GET(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(401);
  });
});
