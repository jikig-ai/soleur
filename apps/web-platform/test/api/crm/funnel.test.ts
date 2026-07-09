import { describe, test, expect, vi, beforeEach } from "vitest";
import { computeFunnel, LOW_N_THRESHOLD } from "@/app/api/crm/funnel/compute";

// GET /api/crm/funnel (feat-beta-crm-ui #6172) + the pure computeFunnel().

const { mockGetUser, mockFrom, mockCaptureException } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: mockCaptureException }));

import { GET } from "@/app/api/crm/funnel/route";

function queryResult(result: { data: unknown; error: unknown }) {
  const chain: Record<string, unknown> = {};
  chain.select = () => chain;
  chain.then = (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) =>
    Promise.resolve(result).then(res, rej);
  return chain;
}

const D = (day: string) => `2026-${day}T00:00:00Z`;

describe("computeFunnel (pure)", () => {
  test("reached is cumulative, derived from current stage + transitions; every contact reaches 'new'", () => {
    // 3 contacts: one still 'new' (no transitions), two advanced.
    const contacts = [
      { id: "a", stage: "new", created_at: D("06-01") },
      { id: "b", stage: "qualified", created_at: D("06-01") },
      { id: "c", stage: "committed", created_at: D("06-01") },
    ];
    const transitions = [
      { contact_id: "b", from_stage: "new", to_stage: "contacted", entered_at: D("06-03") },
      { contact_id: "b", from_stage: "contacted", to_stage: "qualified", entered_at: D("06-06") },
      { contact_id: "c", from_stage: "new", to_stage: "contacted", entered_at: D("06-02") },
      { contact_id: "c", from_stage: "contacted", to_stage: "qualified", entered_at: D("06-05") },
      { contact_id: "c", from_stage: "qualified", to_stage: "evaluating", entered_at: D("06-08") },
      { contact_id: "c", from_stage: "evaluating", to_stage: "committed", entered_at: D("06-12") },
    ];
    const r = computeFunnel(contacts, transitions);
    const reached = Object.fromEntries(r.stages.map((s) => [s.stage, s.reached]));
    expect(reached.new).toBe(3); // everyone
    expect(reached.contacted).toBe(2);
    expect(reached.qualified).toBe(2);
    expect(reached.evaluating).toBe(1);
    expect(reached.committed).toBe(1);
    expect(reached.closed_won).toBe(0);
    // Top of funnel has no conversion %.
    expect(r.stages[0].conversionPct).toBeNull();
    // contacted / new = 2/3 → 67
    expect(r.stages[1].conversionPct).toBe(67);
  });

  test("conversionPct is null (insufficient data) when the prior stage's reached < LOW_N_THRESHOLD", () => {
    // Only 2 contacts reach 'new' → below the threshold (3); the contacted % is
    // suppressed even though one advanced.
    expect(LOW_N_THRESHOLD).toBe(3);
    const contacts = [
      { id: "a", stage: "new", created_at: D("06-01") },
      { id: "b", stage: "contacted", created_at: D("06-01") },
    ];
    const transitions = [
      { contact_id: "b", from_stage: "new", to_stage: "contacted", entered_at: D("06-03") },
    ];
    const r = computeFunnel(contacts, transitions);
    expect(r.stages[0].reached).toBe(2); // new
    expect(r.stages[1].stage).toBe("contacted");
    expect(r.stages[1].reached).toBe(1);
    expect(r.stages[1].conversionPct).toBeNull(); // prev(2) < 3
  });

  test("closedLost is counted as a terminal branch (not a funnel stage), with reached history intact", () => {
    const contacts = [
      { id: "a", stage: "closed_lost", created_at: D("06-01") },
      { id: "b", stage: "new", created_at: D("06-01") },
      { id: "c", stage: "new", created_at: D("06-01") },
    ];
    const transitions = [
      { contact_id: "a", from_stage: "new", to_stage: "contacted", entered_at: D("06-02") },
      { contact_id: "a", from_stage: "contacted", to_stage: "closed_lost", entered_at: D("06-05") },
    ];
    const r = computeFunnel(contacts, transitions);
    expect(r.closedLost).toBe(1);
    // 'a' reached contacted before being lost; closed_lost is not a funnel bar.
    expect(r.stages.map((s) => s.stage)).not.toContain("closed_lost");
    const reached = Object.fromEntries(r.stages.map((s) => [s.stage, s.reached]));
    expect(reached.new).toBe(3);
    expect(reached.contacted).toBe(1); // only 'a' ever reached contacted
  });

  test("per-transition velocity: avg days between adjacent funnel entries (new anchors on created_at)", () => {
    const contacts = [{ id: "a", stage: "contacted", created_at: D("06-01") }];
    const transitions = [
      { contact_id: "a", from_stage: "new", to_stage: "contacted", entered_at: D("06-05") },
    ];
    const r = computeFunnel(contacts, transitions);
    const hop = r.perTransition.find((p) => p.from === "new" && p.to === "contacted");
    expect(hop?.avgDays).toBe(4); // Jun 1 -> Jun 5
    expect(r.avgTimeInStageDays).toBe(4);
  });

  test("empty pipeline: all reached 0, avg/perTransition null", () => {
    const r = computeFunnel([], []);
    expect(r.stages.every((s) => s.reached === 0)).toBe(true);
    expect(r.closedLost).toBe(0);
    expect(r.avgTimeInStageDays).toBeNull();
    expect(r.perTransition.every((p) => p.avgDays === null)).toBe(true);
  });
});

describe("GET /api/crm/funnel", () => {
  beforeEach(() => {
    mockGetUser.mockReset();
    mockFrom.mockReset();
    mockCaptureException.mockReset();
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("200 returns the computed funnel", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockFrom.mockImplementation((table: string) => {
      if (table === "beta_contacts") {
        return queryResult({
          data: [
            { id: "a", stage: "new", created_at: D("06-01") },
            { id: "b", stage: "new", created_at: D("06-01") },
            { id: "c", stage: "new", created_at: D("06-01") },
          ],
          error: null,
        });
      }
      return queryResult({ data: [], error: null });
    });

    const res = await GET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.stages[0]).toEqual({ stage: "new", reached: 3, conversionPct: null });
    expect(body.closedLost).toBe(0);
  });

  test("502 + PII-free Sentry mirror when a query errors", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockFrom.mockImplementation((table: string) => {
      if (table === "beta_contacts") {
        return queryResult({
          data: null,
          error: { code: "42P01", message: "relation missing", details: "Acme" },
        });
      }
      return queryResult({ data: [], error: null });
    });

    const res = await GET();
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "funnel_query_error" });
    const [errArg, ctxArg] = mockCaptureException.mock.calls[0];
    expect(JSON.stringify({ m: (errArg as Error).message, c: ctxArg })).not.toMatch(/Acme|relation missing/);
    expect((errArg as Error).message).toBe("crm-funnel:42P01");
  });
});
