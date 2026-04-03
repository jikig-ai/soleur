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
}));

import { POST } from "../app/api/repo/install/route";
import { verifyInstallationOwnership as mockVerifyOwnership } from "../server/github-app";

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

    mockAdminGetUserById.mockResolvedValue({
      data: {
        user: {
          id: "user-abc",
          identities: [
            { provider: "email", identity_data: {} },
            { provider: "github", identity_data: { user_name: "deruelle" } },
          ],
        },
      },
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("returns 403 when no GitHub identity found via admin API", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-xyz",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockAdminGetUserById.mockResolvedValue({
      data: {
        user: {
          id: "user-xyz",
          identities: [
            { provider: "email", identity_data: {} },
          ],
        },
      },
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error).toMatch(/no github identity/i);
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

    mockAdminGetUserById.mockResolvedValue({
      data: {
        user: {
          id: "user-def",
          identities: [
            { provider: "github", identity_data: { user_name: "alice" } },
          ],
        },
      },
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("returns 403 when admin getUserById returns null user", async () => {
    mockGetUser.mockResolvedValue({
      data: {
        user: {
          id: "user-missing",
          identities: null,
          app_metadata: { providers: ["email"] },
        },
      },
    });

    mockAdminGetUserById.mockResolvedValue({
      data: { user: null },
    });

    const res = await POST(makeRequest({ installationId: 100 }));
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error).toMatch(/no github identity/i);
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
