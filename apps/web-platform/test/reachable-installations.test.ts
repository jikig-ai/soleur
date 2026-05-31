import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/server/github-app", () => ({
  findInstallationForLogin: vi.fn(),
  listInstallationRepos: vi.fn(),
  verifyInstallationOwnership: vi.fn(),
  checkRepoAccess: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

import { findInstallationForLogin } from "@/server/github-app";
import * as Sentry from "@sentry/nextjs";
import { resolveReachableInstallationIds } from "@/server/reachable-installations";

const mockFindInstallation = vi.mocked(findInstallationForLogin);

type MembershipRow = {
  workspace_id: string;
  workspaces?: { github_installation_id?: number | null } | null;
};

function mockServiceFrom(opts: {
  memberships?: MembershipRow[];
  membershipError?: unknown;
}) {
  return (table: string) => {
    if (table !== "workspace_members") {
      throw new Error(`unexpected table: ${table}`);
    }
    const builder: Record<string, unknown> = {
      select: () => builder,
      eq: () =>
        Promise.resolve({
          data: opts.membershipError ? null : (opts.memberships ?? []),
          error: opts.membershipError ?? null,
        }),
    };
    return builder;
  };
}

function serviceClient(opts: Parameters<typeof mockServiceFrom>[0]) {
  return { from: mockServiceFrom(opts) } as never;
}

describe("resolveReachableInstallationIds", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("T1: personal-only — login matches an install, no memberships", async () => {
    mockFindInstallation.mockResolvedValue(111);
    const ids = await resolveReachableInstallationIds(
      serviceClient({ memberships: [] }),
      "user-1",
      "octocat",
    );
    expect(ids).toEqual([111]);
  });

  it("T2: org-only — no personal match, one membership with install", async () => {
    mockFindInstallation.mockResolvedValue(null);
    const ids = await resolveReachableInstallationIds(
      serviceClient({
        memberships: [
          { workspace_id: "ws-1", workspaces: { github_installation_id: 222 } },
        ],
      }),
      "user-1",
      "octocat",
    );
    expect(ids).toEqual([222]);
  });

  it("T3: both — personal + membership installs, deduped (order-insensitive)", async () => {
    mockFindInstallation.mockResolvedValue(111);
    const ids = await resolveReachableInstallationIds(
      serviceClient({
        memberships: [
          { workspace_id: "ws-1", workspaces: { github_installation_id: 222 } },
        ],
      }),
      "user-1",
      "octocat",
    );
    expect(ids.sort()).toEqual([111, 222]);
  });

  it("T4: dedupe — personal install == org install → single id", async () => {
    mockFindInstallation.mockResolvedValue(333);
    const ids = await resolveReachableInstallationIds(
      serviceClient({
        memberships: [
          { workspace_id: "ws-1", workspaces: { github_installation_id: 333 } },
        ],
      }),
      "user-1",
      "octocat",
    );
    expect(ids).toEqual([333]);
  });

  it("T5: membership query error → degrade to personal-only + Sentry", async () => {
    mockFindInstallation.mockResolvedValue(111);
    const ids = await resolveReachableInstallationIds(
      serviceClient({ membershipError: { message: "boom" } }),
      "user-1",
      "octocat",
    );
    expect(ids).toEqual([111]);
    expect(Sentry.captureException).toHaveBeenCalled();
  });

  it("T6: no login, no memberships → []", async () => {
    const ids = await resolveReachableInstallationIds(
      serviceClient({ memberships: [] }),
      "user-1",
      null,
    );
    expect(ids).toEqual([]);
    expect(mockFindInstallation).not.toHaveBeenCalled();
  });
});
