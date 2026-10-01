import { describe, test, expect, vi, beforeEach } from "vitest";

// Route-boundary coverage for /api/workspace/list-memberships (#8978 review):
// pin the verifiedUserId() → resolveOrgMemberships(userId, service) wiring and
// the 401-on-unauthenticated contract. The resolver's own unit coverage lives
// in org-memberships-resolver.test.ts.

const { mockGetUser, mockResolve } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockResolve: vi.fn(),
}));

const serviceClientSentinel = { from: vi.fn() };

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => serviceClientSentinel),
}));
vi.mock("@/server/org-memberships-resolver", () => ({
  resolveOrgMemberships: mockResolve,
}));
vi.mock("@sentry/nextjs", () => ({ addBreadcrumb: vi.fn() }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));

import { GET } from "@/app/api/workspace/list-memberships/route";

function req(headers: Record<string, string> = {}): Request {
  return new Request("https://app.soleur.ai/api/workspace/list-memberships", {
    headers,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockResolve.mockResolvedValue([{ organizationId: "org-1" }]);
  mockGetUser.mockResolvedValue({
    data: { user: { id: "u-remote" } },
    error: null,
  });
});

describe("GET /api/workspace/list-memberships", () => {
  test("minted header → resolver called with (userId, service), zero remote getUser", async () => {
    const res = await GET(req({ "x-soleur-auth-user-id": "u-minted" }));
    expect(res.status).toBe(200);
    expect(mockResolve).toHaveBeenCalledWith("u-minted", serviceClientSentinel);
    expect(mockGetUser).not.toHaveBeenCalled();
    const body = await res.json();
    expect(body.memberships).toEqual([{ organizationId: "org-1" }]);
  });

  test("absent header → getUser fallback → resolver sees the remote id", async () => {
    const res = await GET(req());
    expect(res.status).toBe(200);
    expect(mockGetUser).toHaveBeenCalledTimes(1);
    expect(mockResolve).toHaveBeenCalledWith("u-remote", serviceClientSentinel);
  });

  test("unauthenticated (no header + getUser null) → 401 {memberships:[]}, resolver never called", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const res = await GET(req());
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ memberships: [] });
    expect(mockResolve).not.toHaveBeenCalled();
  });
});
