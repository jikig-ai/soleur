import { describe, test, expect, vi, beforeEach } from "vitest";

// PR-H (#3244) Phase 6 — /api/dashboard/today server route (multi-source).
//
// Returns drafts filtered to status=draft AND tier IN (external_brand_critical,
// external_low_stakes). Inline-ranked + sliced to ≤7 items; remainder in
// `extras`. Cache-Control: private, max-age=60 (Art. 14 minimization).

const { mockGetUser, mockEq, mockIn, mockOrder, mockLimit, mockSelect, mockFrom } = vi.hoisted(() => {
  const mockLimit = vi.fn();
  const mockOrder = vi.fn(() => ({ limit: mockLimit }));
  const mockIn = vi.fn(() => ({ eq: mockEq, in: mockIn, order: mockOrder }));
  const mockEq: ReturnType<typeof vi.fn> = vi.fn(() => ({
    eq: mockEq,
    in: mockIn,
    order: mockOrder,
  }));
  const mockSelect = vi.fn(() => ({ eq: mockEq, in: mockIn, order: mockOrder }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return { mockGetUser: vi.fn(), mockEq, mockIn, mockOrder, mockLimit, mockSelect, mockFrom };
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

function fixtureRow(overrides: Partial<{ id: string; urgency: string; source: string; sourceRef: string | null; createdAt: string }>) {
  return {
    id: overrides.id ?? "msg-x",
    source: overrides.source ?? "stripe",
    source_ref: overrides.sourceRef ?? null,
    owning_domain: "cfo",
    draft_preview: "hello",
    urgency: overrides.urgency ?? "medium",
    created_at: overrides.createdAt ?? "2026-05-19T12:00:00Z",
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockLimit.mockResolvedValue({ data: [], error: null });
  mockGetUser.mockResolvedValue({
    data: { user: { id: "founder-A" } },
    error: null,
  });
});

describe("/api/dashboard/today (PR-H)", () => {
  test("returns 401 when no authenticated user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(401);
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("queries messages with tier IN (external_brand_critical, external_low_stakes) AND status=draft", async () => {
    await GET(makeRequest());
    expect(mockFrom).toHaveBeenCalledWith("messages");
    expect(mockIn).toHaveBeenCalledWith("tier", [
      "external_brand_critical",
      "external_low_stakes",
    ]);
    expect(mockEq).toHaveBeenCalledWith("user_id", "founder-A");
    expect(mockEq).toHaveBeenCalledWith("status", "draft");
  });

  test("returns { items: [], extras: [] } on empty result", async () => {
    mockLimit.mockResolvedValue({ data: [], error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: unknown[]; extras: unknown[] };
    expect(body.items).toEqual([]);
    expect(body.extras).toEqual([]);
  });

  test("returns the disclosure constant alongside items (agent-parity)", async () => {
    const res = await GET(makeRequest());
    const body = (await res.json()) as { disclosure: string };
    expect(body.disclosure).toMatch(/disclaims warranty for runtime cost/);
  });

  test("AC7: 30 mock items → items.length === 7 AND extras.length === 23", async () => {
    const rows = Array.from({ length: 30 }, (_, i) =>
      fixtureRow({
        id: `msg-${i}`,
        urgency: "normal",
        createdAt: new Date(2026, 4, 19, 12, i).toISOString(),
      }),
    );
    mockLimit.mockResolvedValue({ data: rows, error: null });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: unknown[]; extras: unknown[] };
    expect(body.items).toHaveLength(7);
    expect(body.extras).toHaveLength(23);
  });

  test("strict-tier ordering: critical → high → medium → normal → low", async () => {
    mockLimit.mockResolvedValue({
      data: [
        fixtureRow({ id: "low-1", urgency: "low" }),
        fixtureRow({ id: "critical-1", urgency: "critical" }),
        fixtureRow({ id: "normal-1", urgency: "normal" }),
        fixtureRow({ id: "high-1", urgency: "high" }),
        fixtureRow({ id: "medium-1", urgency: "medium" }),
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { id: string; urgency: string }[] };
    expect(body.items.map((i) => i.id)).toEqual([
      "critical-1",
      "high-1",
      "medium-1",
      "normal-1",
      "low-1",
    ]);
  });

  test("returns Cache-Control: private, max-age=60 (Art. 14 minimization)", async () => {
    const res = await GET(makeRequest());
    expect(res.headers.get("cache-control")).toBe("private, max-age=60");
  });

  test("returns 500 on DB read error", async () => {
    mockLimit.mockResolvedValue({ data: null, error: { message: "boom" } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(500);
  });

  test("widens response item to include sourceRef (camelCase)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        fixtureRow({
          id: "msg-pr-1",
          source: "github",
          sourceRef: "pr-jikig-ai-soleur-4066",
          urgency: "normal",
        }),
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { sourceRef: string; source: string }[] };
    expect(body.items[0].source).toBe("github");
    expect(body.items[0].sourceRef).toBe("pr-jikig-ai-soleur-4066");
  });
});
