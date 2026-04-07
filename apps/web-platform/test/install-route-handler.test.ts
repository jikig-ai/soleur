import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock modules BEFORE importing the route handler
// ---------------------------------------------------------------------------

const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { admin: { getUserById: mockAdminGetUserById } },
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

vi.mock("@/server/github-app", () => ({
  verifyInstallationOwnership: vi.fn(),
  getInstallationAccount: vi.fn(),
}));

import { POST } from "../app/api/repo/install/route";
import { verifyInstallationOwnership as mockVerifyOwnership, getInstallationAccount as mockGetInstallationAccount } from "../server/github-app";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(body: Record<string, unknown>) {
  return new Request("https://app.soleur.ai/api/repo/install", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
}

/** Mock the admin getUserById response with the given identities list. */
function mockIdentitiesQuery(
  userId: string,
  identities: Array<{ provider: string; identity_data: Record<string, unknown> }> | null,
) {
  mockAdminGetUserById.mockResolvedValue({
    data: {
      user: identities === null ? null : { id: userId, identities },
    },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/repo/install — identity resolution", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    (mockVerifyOwnership as ReturnType<typeof vi.fn>).mockResolvedValue({
      verified: true,
    });
    mockServiceFrom.mockReturnValue({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });
  });

  test("succeeds when user.identities is null but admin API has GitHub record", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-abc",
          identities: null,
          app_metadata: { providers: ["email", "github"] },
        },
      },
    });

    mockIdentitiesQuery("user-abc", [
      { provider: "email", identity_data: {} },
      { provider: "github", identity_data: { user_name: "deruelle" } },
    ]);

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("email-only user via admin API: succeeds when installation exists", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-xyz",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-xyz", [
      { provider: "email", identity_data: {} },
    ]);
    // Installation exists
    vi.mocked(mockGetInstallationAccount).mockResolvedValue({
      login: "someuser",
      id: 1,
      type: "User",
    });
    mockServiceFrom.mockReturnValue({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
  });

  test("succeeds when admin API returns GitHub identity (standard flow)", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-def",
          identities: [
            { provider: "github", identity_data: { user_name: "alice" } },
          ],
          app_metadata: { providers: ["github"] },
        },
      },
    });

    mockIdentitiesQuery("user-def", [
      { provider: "github", identity_data: { user_name: "alice" } },
    ]);

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("email-only user: stores installation when it exists", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-email-only",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-email-only", null);
    // getInstallationAccount succeeds — installation exists
    vi.mocked(mockGetInstallationAccount).mockResolvedValue({
      login: "someuser",
      id: 1,
      type: "User",
    });
    mockServiceFrom.mockReturnValue({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
  });

  test("email-only user: returns 404 when installation does not exist", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-email-only-2",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockIdentitiesQuery("user-email-only-2", null);
    // getInstallationAccount throws — installation not found
    vi.mocked(mockGetInstallationAccount).mockRejectedValue(new Error("Installation not found"));

    const res = await POST(makeRequest({ installationId: 999 }));
    expect(res.status).toBe(404);
  });

  test("returns 500 with descriptive error when getUserById throws", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-crash",
          identities: null,
          app_metadata: { providers: ["email", "github"] },
        },
      },
    });

    mockAdminGetUserById.mockRejectedValue(
      new Error("localStorage is not defined"),
    );

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to resolve/i);
  });
});
