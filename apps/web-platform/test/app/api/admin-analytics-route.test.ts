import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// GAP H (ADR-067 staleTimes amendment): the admin-gated analytics data route.
// Its isAdmin gate re-runs on every fetch (this is what makes a de-provisioned
// admin get a fresh 403 instead of a warm-cached all-tenant RSC).

const { getUserMock } = vi.hoisted(() => ({ getUserMock: vi.fn() }));

let usersResult: { data: unknown[] | null; error: unknown };
let convsResult: { data: unknown[] | null; error: unknown };

function makeServiceClient() {
  return {
    from: (table: string) => ({
      select: () => ({
        order: () => {
          if (table === "users") return Promise.resolve(usersResult);
          // conversations: .order().limit()
          return { limit: () => Promise.resolve(convsResult) };
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
    const res = await GET();
    expect(res.status).toBe(401);
  });

  it("403 when authenticated but NOT in ADMIN_USER_IDS (de-provisioned admin)", async () => {
    getUserMock.mockResolvedValue({
      data: { user: { id: "11111111-1111-1111-1111-111111111111" } },
    });
    const res = await GET();
    expect(res.status).toBe(403);
  });

  it("403 when ADMIN_USER_IDS env is missing (fail-closed)", async () => {
    vi.stubEnv("ADMIN_USER_IDS", "");
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET();
    expect(res.status).toBe(403);
  });

  it("200 with { metrics, funnel } for an admin", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    const res = await GET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toHaveProperty("metrics");
    expect(body).toHaveProperty("funnel");
    expect(Array.isArray(body.metrics)).toBe(true);
  });

  it("500 when the all-tenant query errors", async () => {
    getUserMock.mockResolvedValue({ data: { user: { id: ADMIN_ID } } });
    usersResult = { data: null, error: { message: "boom" } };
    const res = await GET();
    expect(res.status).toBe(500);
  });
});
