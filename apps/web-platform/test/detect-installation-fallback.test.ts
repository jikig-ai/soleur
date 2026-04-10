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
// Table-routing helpers for mockServiceFrom
// ---------------------------------------------------------------------------
type TableOperation = "select" | "update";
type TableMockConfig = Record<string, Partial<Record<TableOperation, unknown>>>;

/**
 * Configure mockServiceFrom to route by table name + operation instead of
 * relying on positional mockReturnValueOnce chains.
 */
function setupTableRoutes(config: TableMockConfig) {
  mockServiceFrom.mockImplementation((table: string) => {
    const tableConfig = config[table];
    if (!tableConfig) {
      throw new Error(`Unexpected .from("${table}") call — add it to setupTableRoutes`);
    }
    const mock: Record<string, unknown> = {};
    if (tableConfig.select !== undefined) {
      mock.select = vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({ data: tableConfig.select }),
        }),
      });
    }
    if (tableConfig.update !== undefined) {
      mock.update = vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: tableConfig.update }),
      });
    }
    return mock;
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
    // Route .from("users") to return select data and accept updates
    setupTableRoutes({
      users: {
        select: { github_installation_id: null, github_username: "deruelle" },
        update: null, // no error
      },
    });

    // No GitHub identity in Supabase
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { id: "user-123", identities: [{ provider: "email", identity_data: {} }] } },
    });

    // Installation found
    mockFindInstallationForLogin.mockResolvedValue(12345);
    mockVerifyInstallationOwnership.mockResolvedValue({ verified: true });
    mockListInstallationRepos.mockResolvedValue([{ name: "my-repo", fullName: "deruelle/my-repo" }]);

    const response = await POST(makeRequest());
    const data = await response.json();

    expect(data.installed).toBe(true);
    expect(data.repos).toHaveLength(1);
    expect(mockFindInstallationForLogin).toHaveBeenCalledWith("deruelle");
  });

  test("returns no_github_identity when neither Supabase identity nor github_username exists", async () => {
    // Route .from("users") — no installation ID or username
    setupTableRoutes({
      users: {
        select: { github_installation_id: null, github_username: null },
      },
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
    // Route .from("users") — no installation ID, accept updates
    setupTableRoutes({
      users: {
        select: { github_installation_id: null },
        update: null, // no error
      },
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

    const response = await POST(makeRequest());
    const data = await response.json();

    expect(data.installed).toBe(true);
    // Should use Supabase identity, not stored github_username
    expect(mockFindInstallationForLogin).toHaveBeenCalledWith("supabase-user");
  });
});
