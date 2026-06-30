import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-repo-connect-block-offer-join — unit coverage for the connect-time guard
// that blocks a SECOND solo workspace from binding a repo already owned by a
// different solo workspace under the same installation (WEB-PLATFORM-3M), and
// redirects the caller to SWITCH when the owning solo is their own + ready.
//
// The guard's branch logic is the unit under test; the underlying resolver
// (resolveSoloFounderForInstallation) is already covered by its own suite and
// is mocked here so each of the guard's six branches can be driven directly.

const mockResolve = vi.fn();
vi.mock("@/server/resolve-founder-for-installation", () => ({
  resolveSoloFounderForInstallation: (...args: unknown[]) => mockResolve(...args),
}));

const mockReport = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => mockReport(...args),
}));

import { evaluateRepoConnect } from "@/server/repo-connect-guard";

const INSTALL = 4242;
const REPO = "https://github.com/octo/repo";
// Solo invariant (ADR-038 N2): a solo workspace id equals its owner's user id.
const USER = "11111111-1111-1111-1111-111111111111"; // caller == caller's own solo id
const ACTIVE_TEAM = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"; // a team ws the caller acts in
const OTHER = "99999999-9999-9999-9999-999999999999"; // a DIFFERENT user's solo id

// Service-client mock that answers ONLY the `repo_status` read keyed on the
// founder id. `repoStatus === undefined` simulates a workspaces row that has no
// repo_status (or no row). Throws on any other table so a stray read is caught.
function makeService(repoStatus?: string | null) {
  const eqCols: string[] = [];
  const client = {
    eqCols,
    from: (table: string) => {
      if (table !== "workspaces") throw new Error(`unexpected table: ${table}`);
      const chain = {
        select: (_cols: string) => chain,
        eq: (col: string, _val: string | number) => {
          eqCols.push(col);
          return chain;
        },
        maybeSingle: () =>
          Promise.resolve({
            data: repoStatus === undefined ? null : { repo_status: repoStatus },
            error: null,
          }),
      };
      return chain;
    },
  };
  return client as never;
}

const base = {
  installationId: INSTALL,
  repoUrl: REPO,
  userId: USER,
};

describe("evaluateRepoConnect", () => {
  beforeEach(() => vi.clearAllMocks());

  test("none → proceed (ok), no repo_status read", async () => {
    mockResolve.mockResolvedValue({ kind: "none" });
    const svc = makeService();
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM,
      serviceClient: svc,
    });
    expect(result).toEqual({ outcome: "ok" });
    // none → no caller's-own arm → no repo_status read
    expect((svc as unknown as { eqCols: string[] }).eqCols).toHaveLength(0);
  });

  test("found, founderId == activeWorkspaceId → proceed (re-connect/no-op)", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: ACTIVE_TEAM });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM,
      serviceClient: makeService(),
    });
    expect(result).toEqual({ outcome: "ok" });
  });

  test("found, caller's own solo owns it AND ready → switch carrying caller's own id", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: USER });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM, // acting from a team; own solo owns the repo
      serviceClient: makeService("ready"),
    });
    expect(result).toEqual({
      outcome: "switch",
      code: "workspace_switch_required",
      existingWorkspaceId: USER,
      canRequestJoin: false,
    });
  });

  test("found, caller's own solo owns it but NOT ready → decline (no switch into not-ready)", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: USER });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM,
      serviceClient: makeService("cloning"),
    });
    expect(result).toEqual({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    });
    // GAP-2: a not-ready own workspace must NOT leak existingWorkspaceId.
    expect(result).not.toHaveProperty("existingWorkspaceId");
  });

  test("found, a DIFFERENT user's solo owns it → decline", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: OTHER });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: USER, // acting from own solo; another user owns the repo
      serviceClient: makeService(),
    });
    expect(result).toEqual({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    });
  });

  // Security P1: the different-user decline must NOT serialize the victim's
  // founderId / existingWorkspaceId anywhere in the structured outcome.
  test("different-user decline never serializes founderId / existingWorkspaceId", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: OTHER });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: USER,
      serviceClient: makeService(),
    });
    const serialized = JSON.stringify(result);
    expect(serialized).not.toContain(OTHER);
    expect(serialized).not.toContain("existingWorkspaceId");
    expect(serialized).not.toContain("founderId");
  });

  // Branch order is load-bearing: when activeWorkspaceId == userId == founderId
  // (a solo user reconnecting from their own active solo), the activeWorkspaceId
  // arm must win → proceed, NOT switch-into-the-workspace-they-are-already-in.
  test("activeWorkspaceId == userId == founderId → proceed (not switch)", async () => {
    mockResolve.mockResolvedValue({ kind: "found", founderId: USER });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: USER,
      serviceClient: makeService("ready"),
    });
    expect(result).toEqual({ outcome: "ok" });
  });

  test("ambiguous → decline + fail-closed Sentry mirror", async () => {
    mockResolve.mockResolvedValue({ kind: "ambiguous", count: 2 });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM,
      serviceClient: makeService(),
    });
    expect(result).toEqual({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    });
    expect(mockReport).toHaveBeenCalledTimes(1);
  });

  test("db-error → decline + fail-closed Sentry mirror", async () => {
    mockResolve.mockResolvedValue({ kind: "db-error" });
    const result = await evaluateRepoConnect({
      ...base,
      activeWorkspaceId: ACTIVE_TEAM,
      serviceClient: makeService(),
    });
    expect(result).toEqual({
      outcome: "decline",
      code: "repo_connect_blocked",
      canRequestJoin: false,
    });
    expect(mockReport).toHaveBeenCalledTimes(1);
  });
});
