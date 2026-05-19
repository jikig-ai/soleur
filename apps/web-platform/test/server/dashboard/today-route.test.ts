import { describe, test, expect, vi, beforeEach } from "vitest";

// PR-F (#3244, #3940) Phase 5 — /api/dashboard/today server route.
//
// Returns the caller's draft messages filtered to tier=external_brand_critical
// AND status=draft. RLS at the table level isolates founders from each other;
// the route uses createClient() (cookie-scoped authed client) rather than
// service-role, so a malformed query CANNOT leak cross-founder rows.

const { mockGetUser, mockEq, mockOrder, mockLimit, mockSelect, mockFrom } = vi.hoisted(() => {
  const mockLimit = vi.fn();
  const mockOrder = vi.fn(() => ({ limit: mockLimit }));
  const mockEq = vi.fn(() => ({ eq: mockEq, order: mockOrder }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return {
    mockGetUser: vi.fn(),
    mockEq,
    mockOrder,
    mockLimit,
    mockSelect,
    mockFrom,
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

import { GET } from "@/app/api/dashboard/today/route";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/dashboard/today");
}

beforeEach(() => {
  vi.clearAllMocks();
  mockLimit.mockResolvedValue({ data: [], error: null });
  mockGetUser.mockResolvedValue({
    data: { user: { id: "founder-A" } },
    error: null,
  });
});

describe("/api/dashboard/today", () => {
  test("returns 401 when no authenticated user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(401);
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("queries messages filtered by tier=external_brand_critical AND status=draft for the authenticated caller", async () => {
    await GET(makeRequest());
    expect(mockFrom).toHaveBeenCalledWith("messages");
    // The three .eq() filters: user_id (RLS belt-and-suspenders),
    // tier='external_brand_critical', status='draft'.
    const eqCalls = mockEq.mock.calls.map((c) => (c as unknown[])[0]);
    expect(eqCalls).toEqual(
      expect.arrayContaining(["user_id", "tier", "status"]),
    );
    expect(mockEq).toHaveBeenCalledWith("user_id", "founder-A");
    expect(mockEq).toHaveBeenCalledWith("tier", "external_brand_critical");
    expect(mockEq).toHaveBeenCalledWith("status", "draft");
  });

  test("returns { items: [] } on empty result (200)", async () => {
    mockLimit.mockResolvedValue({ data: [], error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: unknown[] };
    expect(body.items).toEqual([]);
  });

  // Review P2-7 (agent-native-reviewer): the legal disclosure ships in
  // the JSON response so agent / MCP / CLI callers do not need to
  // scrape the HTML banner.
  test("returns the disclosure constant alongside items (agent-parity)", async () => {
    mockLimit.mockResolvedValue({ data: [], error: null });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: unknown[]; disclosure: string };
    expect(body.disclosure).toMatch(/disclaims warranty for runtime cost/);
  });

  test("returns the row set as { items: [...] } on hit", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          id: "msg-1",
          source: "stripe",
          owning_domain: "cfo",
          draft_preview: "Hi founder…",
          urgency: "medium",
        },
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: { id: string }[] };
    expect(body.items).toHaveLength(1);
    expect(body.items[0].id).toBe("msg-1");
  });

  test("returns 500 + reports when the DB read errors", async () => {
    mockLimit.mockResolvedValue({
      data: null,
      error: { message: "boom" },
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(500);
  });
});
