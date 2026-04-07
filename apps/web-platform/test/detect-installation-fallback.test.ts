import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock modules BEFORE importing the route handler
// ---------------------------------------------------------------------------

const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();
const mockFindInstallationForLogin = vi.fn();
const mockVerifyInstallationOwnership = vi.fn();
const mockListInstallationRepos = vi.fn();

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
  findInstallationForLogin: (...args: unknown[]) => mockFindInstallationForLogin(...args),
  verifyInstallationOwnership: (...args: unknown[]) => mockVerifyInstallationOwnership(...args),
  listInstallationRepos: (...args: unknown[]) => mockListInstallationRepos(...args),
}));

import { POST } from "../app/api/repo/detect-installation/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest() {
  return new Request("https://app.soleur.ai/api/repo/detect-installation", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
  });
}

// ---------------------------------------------------------------------------
// Tests: github_username fallback
// ---------------------------------------------------------------------------

describe("POST /api/repo/detect-installation — github_username fallback", () => {
  beforeEach(() => {
    vi.resetAllMocks();

    // Default: authenticated user
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-123" } },
    });
  });

  test("uses stored github_username when no Supabase GitHub identity exists", async () => {
    // No github_installation_id but github_username stored from prior OAuth resolve
    mockServiceFrom.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: { github_installation_id: null, github_username: "deruelle" },
          }),
        }),
      }),
    });

    // No GitHub identity in Supabase
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { id: "user-123", identities: [{ provider: "email", identity_data: {} }] } },
    });

    // Installation found
    mockFindInstallationForLogin.mockResolvedValue(12345);
    mockVerifyInstallationOwnership.mockResolvedValue({ verified: true });
    mockListInstallationRepos.mockResolvedValue([{ name: "my-repo", fullName: "deruelle/my-repo" }]);

    // Update call to store installation_id
    mockServiceFrom.mockReturnValueOnce({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });

    const response = await POST(makeRequest());
    const data = await response.json();

    expect(data.installed).toBe(true);
    expect(data.repos).toHaveLength(1);
    expect(mockFindInstallationForLogin).toHaveBeenCalledWith("deruelle");
  });

  test("returns no_github_identity when neither Supabase identity nor github_username exists", async () => {
    // No github_installation_id and no github_username
    mockServiceFrom.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: { github_installation_id: null, github_username: null },
          }),
        }),
      }),
    });

    // No GitHub identity in Supabase
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { id: "user-123", identities: [{ provider: "email", identity_data: {} }] } },
    });

    const response = await POST(makeRequest());
    const data = await response.json();

    expect(data.installed).toBe(false);
    expect(data.reason).toBe("no_github_identity");
  });

  test("prefers Supabase GitHub identity over stored github_username", async () => {
    // No github_installation_id stored
    mockServiceFrom.mockReturnValueOnce({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({ data: { github_installation_id: null } }),
        }),
      }),
    });

    // Has GitHub identity in Supabase
    mockAdminGetUserById.mockResolvedValue({
      data: {
        user: {
          id: "user-123",
          identities: [
            { provider: "github", identity_data: { user_name: "supabase-user" } },
          ],
        },
      },
    });

    // Installation found
    mockFindInstallationForLogin.mockResolvedValue(99999);
    mockVerifyInstallationOwnership.mockResolvedValue({ verified: true });
    mockListInstallationRepos.mockResolvedValue([{ name: "repo", fullName: "supabase-user/repo" }]);

    // Update call
    mockServiceFrom.mockReturnValueOnce({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });

    const response = await POST(makeRequest());
    const data = await response.json();

    expect(data.installed).toBe(true);
    // Should use Supabase identity, not stored github_username
    expect(mockFindInstallationForLogin).toHaveBeenCalledWith("supabase-user");
  });
});
