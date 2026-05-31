import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-skip-api-key-onboarding (#4642) — AC6. GET /api/byok/effective-status
// returns { hasEffectiveKey, pendingDelegation } for the degraded banner.
//  - userId STRICTLY from supabase.auth.getUser() — any ?userId / body param
//    is ignored (IDOR guard).
//  - hasEffectiveKey is computed fail-CLOSED (onErrorReturn:false) so a
//    transient error shows the banner rather than hiding it and lying.
//  - never serializes a ByokDelegationError subtype — bare booleans only.

const {
  mockGetUser,
  mockUserHasEffectiveByokKey,
  mockUserHasPendingByokDelegation,
  mockUserIsSharedWorkspaceMember,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockUserHasEffectiveByokKey: vi.fn(),
  mockUserHasPendingByokDelegation: vi.fn(),
  mockUserIsSharedWorkspaceMember: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
}));

vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
  userHasPendingByokDelegation: mockUserHasPendingByokDelegation,
}));

vi.mock("@/server/workspace-resolver", () => ({
  userIsSharedWorkspaceMember: mockUserIsSharedWorkspaceMember,
}));

import { GET } from "@/app/api/byok/effective-status/route";

const USER_ID = "user-status-uuid";

function makeRequest(url = "https://app.soleur.ai/api/byok/effective-status"): Request {
  return new Request(url, { method: "GET" });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID } } });
  mockUserHasEffectiveByokKey.mockResolvedValue(true);
  mockUserHasPendingByokDelegation.mockResolvedValue(false);
  mockUserIsSharedWorkspaceMember.mockResolvedValue(false);
});

describe("GET /api/byok/effective-status (AC6)", () => {
  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(401);
  });

  test("returns hasEffectiveKey:true for a user with a usable key", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      hasEffectiveKey: true,
      pendingDelegation: false,
      isSharedWorkspaceMember: false,
    });
  });

  test("returns hasEffectiveKey:false + pendingDelegation:true for a grant-holder", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    mockUserHasPendingByokDelegation.mockResolvedValue(true);
    const res = await GET(makeRequest());
    expect(await res.json()).toEqual({
      hasEffectiveKey: false,
      pendingDelegation: true,
      isSharedWorkspaceMember: false,
    });
  });

  test("plumbs isSharedWorkspaceMember:true (#4715), session-derived only", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    mockUserIsSharedWorkspaceMember.mockResolvedValue(true);
    const res = await GET(
      makeRequest("https://app.soleur.ai/api/byok/effective-status?userId=attacker-uuid"),
    );
    expect(await res.json()).toEqual({
      hasEffectiveKey: false,
      pendingDelegation: false,
      isSharedWorkspaceMember: true,
    });
    // IDOR guard preserved — resolved from the authed session, never the query.
    const calledUserIds = mockUserIsSharedWorkspaceMember.mock.calls.map((c) => c[0]);
    expect(calledUserIds).toEqual([USER_ID]);
  });

  test("computes hasEffectiveKey fail-closed (onErrorReturn:false)", async () => {
    await GET(makeRequest());
    expect(mockUserHasEffectiveByokKey).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({ onErrorReturn: false }),
    );
  });

  test("IDOR: ignores a ?userId override — resolves the authed user only", async () => {
    await GET(makeRequest("https://app.soleur.ai/api/byok/effective-status?userId=attacker-uuid"));
    expect(mockUserHasEffectiveByokKey).toHaveBeenCalledWith(USER_ID, expect.anything());
    expect(mockUserHasEffectiveByokKey).not.toHaveBeenCalledWith(
      "attacker-uuid",
      expect.anything(),
    );
    expect(mockUserHasPendingByokDelegation).toHaveBeenCalledWith(USER_ID);
  });
});
