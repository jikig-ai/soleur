import { describe, test, expect, vi, beforeEach } from "vitest";

const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();
const mockAdminGetUserById = vi.fn();
const mockListInstallationRepos = vi.fn();
const mockResolveReachable = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: mockGetUser } }),
  createServiceClient: () => ({
    from: mockServiceFrom,
    auth: { admin: { getUserById: mockAdminGetUserById } },
  }),
}));

vi.mock("@/server/github-app", () => ({
  listInstallationRepos: (...args: unknown[]) =>
    mockListInstallationRepos(...args),
}));

vi.mock("@/server/reachable-installations", () => ({
  resolveReachableInstallationIds: (...args: unknown[]) =>
    mockResolveReachable(...args),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

import { GET } from "../app/api/repo/repos/route";

function makeRepo(fullName: string) {
  return {
    name: fullName.split("/")[1],
    fullName,
    private: false,
    description: null,
    language: null,
    updatedAt: "2026-01-01T00:00:00Z",
  };
}

describe("GET /api/repo/repos — reachable installs", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } } });
    // users.select(github_username).eq().single()
    mockServiceFrom.mockImplementation((table: string) => {
      if (table === "users") {
        return {
          select: () => ({
            eq: () => ({
              single: async () => ({
                data: { github_username: "deruelle" },
                error: null,
              }),
            }),
          }),
        };
      }
      throw new Error(`unexpected table: ${table}`);
    });
    // No GitHub identity in Supabase → falls back to github_username
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { identities: [] } },
      error: null,
    });
  });

  test("T7: two reachable installs → repos aggregated + deduped by fullName", async () => {
    mockResolveReachable.mockResolvedValue([111, 122213433]);
    mockListInstallationRepos.mockImplementation(async (id: number) =>
      id === 111
        ? [makeRepo("deruelle/a"), makeRepo("org/shared")]
        : [makeRepo("org/shared"), makeRepo("jikig-ai/soleur")],
    );

    const res = await GET();
    expect(res.status).toBe(200);
    const body = await res.json();
    const fullNames = body.repos
      .map((r: { fullName: string }) => r.fullName)
      .sort();
    expect(fullNames).toEqual(["deruelle/a", "jikig-ai/soleur", "org/shared"]);
  });

  test("T8: reachable set empty → 400 (contract preserved)", async () => {
    mockResolveReachable.mockResolvedValue([]);
    const res = await GET();
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe(
      "GitHub App not installed. Please install the app first.",
    );
  });
});
