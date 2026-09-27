import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// GAP H (ADR-067 staleTimes amendment): the admin-gated analytics data route.
// Its isAdmin gate re-runs on every fetch (this is what makes a de-provisioned
// admin get a fresh 403 instead of a warm-cached all-tenant RSC).

const { getUserMock, inFilterSpy, eqFilterSpy } = vi.hoisted(() => ({
  getUserMock: vi.fn(),
  inFilterSpy: vi.fn(),
  eqFilterSpy: vi.fn(),
}));

let usersResult: { data: unknown[] | null; error: unknown };
let convsResult: { data: unknown[] | null; error: unknown };

function makeServiceClient() {
  return {
    from: (table: string) => ({
      select: () => ({
        order: () => {
          const base = {
            // users: .order().eq() is the cohort-scoped terminator
            eq: (...args: unknown[]) => {
              eqFilterSpy(...args);
              return Promise.resolve(usersResult);
            },
            then: (res: (v: unknown) => unknown) =>
              Promise.resolve(
                table === "users" ? usersResult : convsResult,
              ).then(res),
          };
          if (table === "conversations") {
            // conversations: .order().in(...).limit() when scoped, else
            // .order().limit()
            return {
              in: (...args: unknown[]) => {
                inFilterSpy(...args);
                return { limit: () => Promise.resolve(convsResult) };
              },
              limit: () => Promise.resolve(convsResult),
              eq: base.eq,
            };
          }
          return base;
        },
      }),
    }),
  };
}

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({ auth: { getUser: getUserMock } }),
  createServiceClient: () => makeServiceClient(),
}));

import { GET } from "@/app/api/admin/analytics/route";

const ADMIN_ID = "00000000-0000-0000-0000-0000000000ad";

function makeRequest(url = "https://soleur.ai/api/admin/analytics"): Request {
  return new Request(url);
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("ADMIN_USER_IDS", ADMIN_ID);
  usersResult = {
    data: [
      {
        id: ADMIN_ID,
        email: "admin@example.com",
        created_at: "2026-01-01T00:00:00Z",
        kb_sync_history: [],
        workspace_status: "ready",
        cohort_key: "alpha",
      },
    ],
    error: null,
  };
  convsResult = { data: [], error: null };
});

afterEach(() => vi.unstubAllEnvs());

describe("GET /api/admin/analytics (GAP H)", () => {
  it("401 when unauthenticated", async () => {
    getUserMock.mockResolvedValue({ data: { user: null } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(401);
  });

  it("403 when authenticated but NOT in ADMIN_USER_IDS (de-provisioned admin)", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "11111111-1111-1111-1111-111111111111" } },
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(403);
  });

  it("403 when ADMIN_USER_IDS env is missing (fail-closed)", async () => {
    vi.stubEnv("ADMIN_USER_IDS", "");
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(403);
  });

  it("200 with { metrics, funnel } for an admin", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty("metrics");
    expect(body).toHaveProperty("funnel");
    expect(Array.isArray(body.metrics)).toBe(true);
  });

  it("500 when the all-tenant query errors", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    usersResult = { data: null, error: { message: "boom" } };
    const res = await GET(makeRequest());
    expect(res.status).toBe(500);
  });
});

describe("GET /api/admin/analytics?cohort= (#8880)", () => {
  it("filters users by cohort_key and conversations by member ids server-side", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET(
      makeRequest("https://soleur.ai/api/admin/analytics?cohort=alpha"),
    );
    expect(res.status).toBe(200);
    // users: .eq("cohort_key", "alpha") applied server-side
    expect(eqFilterSpy).toHaveBeenCalledWith("cohort_key", "alpha");
    // conversations: .in("user_id", <cohort ids>) applied BEFORE .limit()
    expect(inFilterSpy).toHaveBeenCalledWith("user_id", [ADMIN_ID]);
  });

  it("unscoped request applies no cohort filters", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    expect(eqFilterSpy).not.toHaveBeenCalledWith("cohort_key", expect.anything());
    expect(inFilterSpy).not.toHaveBeenCalled();
  });

  it("scoped request with zero cohort members still applies the .in() filter", async () => {
    usersResult = { data: [], error: null };
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET(
      makeRequest("https://soleur.ai/api/admin/analytics?cohort=nobody"),
    );
    expect(res.status).toBe(200);
    // an empty member list must still filter — never drop to unscoped rows
    expect(inFilterSpy).toHaveBeenCalledWith("user_id", []);
  });
});
