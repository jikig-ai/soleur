import { beforeEach, describe, expect, it, vi } from "vitest";

const { mockGetUser, mockListRecentRuns } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockListRecentRuns: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: mockGetUser } }),
}));
vi.mock("@/server/routines/list-routines", () => ({
  listRecentRuns: mockListRecentRuns,
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { GET } from "@/app/api/dashboard/routines/runs/route";

function req(query: string) {
  return new Request(`https://soleur.ai/api/dashboard/routines/runs${query}`);
}

function lastOpts() {
  return mockListRecentRuns.mock.calls.at(-1)![1];
}

beforeEach(() => {
  mockGetUser.mockReset();
  mockListRecentRuns.mockReset();
  mockGetUser.mockResolvedValue({ data: { user: { id: "op-1" } } });
  mockListRecentRuns.mockResolvedValue({ runs: [], nextCursor: null });
});

describe("GET /api/dashboard/routines/runs — filters", () => {
  it("401 without a session", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(req(""));
    expect(res.status).toBe(401);
    expect(mockListRecentRuns).not.toHaveBeenCalled();
  });

  it("passes a valid routineId through", async () => {
    await GET(req("?routineId=cron-daily-triage"));
    expect(lastOpts()).toMatchObject({ routineId: "cron-daily-triage" });
  });

  it("drops a routineId not in EXPECTED_CRON_FUNCTIONS", async () => {
    await GET(req("?routineId=cron-bogus-not-real"));
    expect(lastOpts().routineId).toBeNull();
  });

  it("accepts status completed/failed but NOT running (client-only)", async () => {
    await GET(req("?status=failed"));
    expect(lastOpts().status).toBe("failed");
    await GET(req("?status=running"));
    expect(lastOpts().status).toBeNull();
    await GET(req("?status=bogus"));
    expect(lastOpts().status).toBeNull();
  });

  it("accepts valid triggerSource and drops invalid", async () => {
    await GET(req("?triggerSource=agent"));
    expect(lastOpts().triggerSource).toBe("agent");
    await GET(req("?triggerSource=bogus"));
    expect(lastOpts().triggerSource).toBeNull();
  });

  it("normalizes a parseable since to ISO and drops an unparseable one", async () => {
    await GET(req("?since=2026-06-01T00:00:00.000Z"));
    expect(lastOpts().since).toBe("2026-06-01T00:00:00.000Z");
    await GET(req("?since=not-a-date"));
    expect(lastOpts().since).toBeNull();
  });
});
