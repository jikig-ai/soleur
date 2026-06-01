import { describe, test, expect, vi, beforeEach } from "vitest";

const mockFindInstallationForLogin = vi.fn();
const mockCheckRepoAccess = vi.fn();
const mockReportSilentFallback = vi.fn();

vi.mock("@/server/github-app", () => ({
  findInstallationForLogin: (...args: unknown[]) =>
    mockFindInstallationForLogin(...args),
  checkRepoAccess: (...args: unknown[]) => mockCheckRepoAccess(...args),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) =>
    mockReportSilentFallback(...args),
}));

import {
  resolveReachableInstallationIds,
  resolveOwningInstallationForRepo,
} from "@/server/reachable-installations";

type MembershipRow = {
  workspaces:
    | { github_installation_id: number | null }
    | { github_installation_id: number | null }[]
    | null;
};

// Spy-capturing service-client mock. The workspace_members chain records the
// `.eq("user_id", <id>)` call so the security test (T4) can assert scoping.
function makeService(opts: {
  memberships?: MembershipRow[];
  membershipError?: unknown;
  eqSpy?: ReturnType<typeof vi.fn>;
}) {
  return {
    from: (table: string) => {
      if (table !== "workspace_members") {
        throw new Error(`unexpected table: ${table}`);
      }
      return {
        select: () => ({
          eq: (col: string, val: string) => {
            opts.eqSpy?.(col, val);
            return Promise.resolve({
              data: opts.membershipError ? null : (opts.memberships ?? []),
              error: opts.membershipError ?? null,
            });
          },
        }),
      };
    },
  } as never;
}

describe("resolveReachableInstallationIds", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("T1: org member, login != org login, install on workspace", async () => {
    mockFindInstallationForLogin.mockResolvedValue(null);
    const service = makeService({
      memberships: [{ workspaces: { github_installation_id: 122213433 } }],
    });
    const ids = await resolveReachableInstallationIds(
      service,
      "754ee124",
      "deruelle",
    );
    expect(ids).toEqual([122213433]);
  });

  test("T3: no login match AND no membership install -> empty set / null", async () => {
    mockFindInstallationForLogin.mockResolvedValue(null);
    const service = makeService({ memberships: [] });
    const ids = await resolveReachableInstallationIds(
      service,
      "754ee124",
      "deruelle",
    );
    expect(ids).toEqual([]);
    expect(await resolveOwningInstallationForRepo([], "o", "r")).toBeNull();
  });

  test("T4 (security): membership read is scoped by .eq('user_id', userId)", async () => {
    mockFindInstallationForLogin.mockResolvedValue(null);
    const eqSpy = vi.fn();
    const service = makeService({ memberships: [], eqSpy });
    await resolveReachableInstallationIds(service, "754ee124", "deruelle");
    expect(eqSpy).toHaveBeenCalledWith("user_id", "754ee124");
  });

  test("T5: union + dedupe — personal install + workspace installs, overlapping", async () => {
    mockFindInstallationForLogin.mockResolvedValue(999);
    const service = makeService({
      memberships: [
        { workspaces: { github_installation_id: 999 } },
        { workspaces: { github_installation_id: 122213433 } },
      ],
    });
    const ids = await resolveReachableInstallationIds(
      service,
      "754ee124",
      "deruelle",
    );
    expect(ids.sort((a, b) => a - b)).toEqual([999, 122213433]);
  });

  test("membership query error -> degrade to login-only + reportSilentFallback", async () => {
    mockFindInstallationForLogin.mockResolvedValue(111);
    const service = makeService({ membershipError: { message: "boom" } });
    const ids = await resolveReachableInstallationIds(
      service,
      "754ee124",
      "deruelle",
    );
    expect(ids).toEqual([111]);
    expect(mockReportSilentFallback).toHaveBeenCalled();
  });

  test("no login, no memberships -> [] (findInstallationForLogin not called)", async () => {
    const service = makeService({ memberships: [] });
    const ids = await resolveReachableInstallationIds(service, "754ee124", null);
    expect(ids).toEqual([]);
    expect(mockFindInstallationForLogin).not.toHaveBeenCalled();
  });
});

describe("resolveOwningInstallationForRepo", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("T2: returns the install whose checkRepoAccess is 'ok'", async () => {
    mockCheckRepoAccess.mockImplementation(async (id: number) =>
      id === 122213433 ? "ok" : "not_found",
    );
    const result = await resolveOwningInstallationForRepo(
      [122213433],
      "jikig-ai",
      "soleur",
    );
    expect(result).toBe(122213433);
    expect(mockCheckRepoAccess).toHaveBeenCalledWith(
      122213433,
      "jikig-ai",
      "soleur",
    );
  });

  test("T6 (resilience): keeps probing past 'degraded' and returns the 'ok' install", async () => {
    mockCheckRepoAccess.mockImplementation(async (id: number) =>
      id === 1 ? "degraded" : "ok",
    );
    const result = await resolveOwningInstallationForRepo(
      [1, 2],
      "jikig-ai",
      "soleur",
    );
    expect(result).toBe(2);
    expect(mockCheckRepoAccess).toHaveBeenCalledTimes(2);
  });

  test("returns null when no reachable install owns the repo", async () => {
    mockCheckRepoAccess.mockResolvedValue("not_found");
    const result = await resolveOwningInstallationForRepo([1, 2], "o", "r");
    expect(result).toBeNull();
  });
});
