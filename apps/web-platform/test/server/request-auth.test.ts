import { describe, test, expect, vi, beforeEach } from "vitest";

// Tests for server/request-auth.ts `verifiedUserId` (perf-dashboard-section-
// load-latency, Phase 2). Contract (interface-contract.md §request-auth):
//
//   verifiedUserId(req: Request): Promise<string | null>
//   - Reads `x-soleur-auth-user-id`; returns it when non-empty. The header is
//     a middleware-minted signal — middleware deletes any inbound copy before
//     the request can reach a handler, so a value present HERE is trusted.
//   - Absent/empty → fall back to (await createClient()).auth.getUser() and
//     return user?.id ?? null. The fallback is the FAIL-CLOSED direction:
//     an absent header NEVER means "trust nothing else" — it means "re-verify".
//     Route-level unit tests that invoke handlers without middleware rely on
//     exactly this path.
//   - A FORGED inbound value only reaches a handler if a route bypasses the
//     matcher entirely — that unreachable path is guarded separately by
//     test/server/middleware-matcher-coverage.test.ts (Guard 1) + the
//     delete-before-any-return pin in test/middleware.test.ts.

const { mockGetUser, mockCreateClient } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockCreateClient: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mockCreateClient,
}));

// request-auth mirrors the absent-header path to a Sentry breadcrumb — mock the
// module so the suite stays hermetic (and the breadcrumb becomes assertable).
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
}));

import { verifiedUserId } from "@/server/request-auth";

function makeRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://app.soleur.ai/api/test", { headers });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({
    data: { user: { id: "user-from-getuser" } },
    error: null,
  });
  mockCreateClient.mockResolvedValue({
    auth: { getUser: mockGetUser },
  });
});

describe("verifiedUserId", () => {
  test("x-soleur-auth-user-id present → returns it WITHOUT a Supabase round-trip", async () => {
    const req = makeRequest({ "x-soleur-auth-user-id": "user-from-header" });

    await expect(verifiedUserId(req)).resolves.toBe("user-from-header");
    // The whole point of the header: skip the getUser() auth-server RTT.
    expect(mockCreateClient).not.toHaveBeenCalled();
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  test("header ABSENT (direct invocation / matcher gap / unit test) → getUser() fallback returns user.id", async () => {
    const req = makeRequest();

    await expect(verifiedUserId(req)).resolves.toBe("user-from-getuser");
    expect(mockGetUser).toHaveBeenCalledTimes(1);
  });

  test("header absent + no session → null (fail-closed: caller 401s)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const req = makeRequest();

    await expect(verifiedUserId(req)).resolves.toBeNull();
    expect(mockGetUser).toHaveBeenCalledTimes(1);
  });

  test("header present but EMPTY string → treated as absent → getUser() fallback", async () => {
    // `req.headers.get` returns "" for an explicitly-empty header value; the
    // contract trusts only a NON-EMPTY value.
    const req = makeRequest({ "x-soleur-auth-user-id": "" });

    await expect(verifiedUserId(req)).resolves.toBe("user-from-getuser");
    expect(mockGetUser).toHaveBeenCalledTimes(1);
  });

  test("a request that never traversed middleware cannot self-assert identity — absent header always re-verifies", async () => {
    // The "non-middleware path" case (route invoked directly in dev/tests, or
    // a future matcher gap): there is no trusted channel, so the fallback is
    // the only honest answer. This is the fail-closed direction that keeps
    // ~70 unmigrated getUser()-only routes and all direct-invocation unit
    // tests correct.
    const req = makeRequest(); // no headers — as if middleware never ran
    await expect(verifiedUserId(req)).resolves.toBe("user-from-getuser");
    expect(mockCreateClient).toHaveBeenCalledTimes(1);
  });
});
