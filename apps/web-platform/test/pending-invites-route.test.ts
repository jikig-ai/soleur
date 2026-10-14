import { describe, test, expect, vi, beforeEach } from "vitest";

// Route-level coverage for /api/workspace/pending-invites (#8978 review):
// the email-sourcing arms (JWT claim ↔ remote getUser) and the sub-agreement
// contract are the PR's only NEW multi-branch route logic — the arms must be
// pinned at the route, not only analogously in identity.test.ts.

const { mockGetUser, mockGetSession, mockGetPendingInvites, mockReport } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockGetSession: vi.fn(),
    mockGetPendingInvites: vi.fn(),
    mockReport: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
  })),
}));
vi.mock("@/server/workspace-invitations", () => ({
  getPendingInvitesForUser: mockGetPendingInvites,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
}));
vi.mock("@sentry/nextjs", () => ({ addBreadcrumb: vi.fn() }));

import { GET } from "@/app/api/workspace/pending-invites/route";

function makeJwt(claims: Record<string, unknown>): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");
  return `${b64({ alg: "ES256", typ: "JWT" })}.${b64(claims)}.sig`;
}

function req(headers: Record<string, string> = {}): Request {
  return new Request("https://app.soleur.ai/api/workspace/pending-invites", {
    headers,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetPendingInvites.mockResolvedValue([{ id: "inv-1" }]);
  mockGetUser.mockResolvedValue({
    data: { user: { id: "u-remote", email: "remote@test.local" } },
    error: null,
  });
  mockGetSession.mockResolvedValue({ data: { session: null }, error: null });
});

describe("GET /api/workspace/pending-invites", () => {
  test("minted header + JWT sub/email agreement → local email, ZERO remote getUser", async () => {
    mockGetSession.mockResolvedValue({
      data: {
        session: {
          access_token: makeJwt({ sub: "u-minted", email: "jwt@test.local" }),
        },
      },
      error: null,
    });

    const res = await GET(req({ "x-soleur-auth-user-id": "u-minted" }));
    expect(res.status).toBe(200);
    // Identity from the minted header; email from the local JWT — no RTT.
    expect(mockGetPendingInvites).toHaveBeenCalledWith(
      "u-minted",
      "jwt@test.local",
    );
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  test("JWT sub disagrees with the verified id → email claim NOT trusted → remote re-verify", async () => {
    mockGetSession.mockResolvedValue({
      data: {
        session: {
          access_token: makeJwt({
            sub: "someone-else",
            email: "other@test.local",
          }),
        },
      },
      error: null,
    });

    const res = await GET(req({ "x-soleur-auth-user-id": "u-minted" }));
    expect(res.status).toBe(200);
    // The divergent JWT email must NOT reach the invitee_email query.
    expect(mockGetUser).toHaveBeenCalledTimes(1);
    expect(mockGetPendingInvites).toHaveBeenCalledWith(
      "u-minted",
      "remote@test.local",
    );
  });

  test.each([
    ["missing email claim", makeJwt({ sub: "u-minted" })],
    ["malformed token", "not-a-jwt"],
  ])("JWT unusable (%s) → remote getUser supplies email", async (_label, token) => {
    mockGetSession.mockResolvedValue({
      data: { session: { access_token: token } },
      error: null,
    });

    const res = await GET(req({ "x-soleur-auth-user-id": "u-minted" }));
    expect(res.status).toBe(200);
    expect(mockGetUser).toHaveBeenCalledTimes(1);
    expect(mockGetPendingInvites).toHaveBeenCalledWith(
      "u-minted",
      "remote@test.local",
    );
  });

  test("absent header → verifiedUserId getUser fallback → remote id + remote email when JWT absent", async () => {
    // No minted header: verifiedUserId runs its own getUser (u-remote);
    // no session → the email arm also re-verifies (the double-RTT arm,
    // accepted as rare).
    const res = await GET(req());
    expect(res.status).toBe(200);
    expect(mockGetPendingInvites).toHaveBeenCalledWith(
      "u-remote",
      "remote@test.local",
    );
  });

  test("unauthenticated (no header + getUser null) → 401, resolver never called", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const res = await GET(req());
    expect(res.status).toBe(401);
    expect(mockGetPendingInvites).not.toHaveBeenCalled();
  });

  test("verified user but email unresolvable (both sources empty) → mirrored, invites queried with ''", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u-minted", email: null } },
      error: null,
    });
    mockGetSession.mockResolvedValue({
      data: {
        session: { access_token: makeJwt({ sub: "u-minted" }) },
      },
      error: null,
    });

    const res = await GET(req({ "x-soleur-auth-user-id": "u-minted" }));
    expect(res.status).toBe(200);
    expect(mockReport).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "pending-invites.email-unresolved",
      }),
    );
    expect(mockGetPendingInvites).toHaveBeenCalledWith("u-minted", "");
  });
});
