import { describe, test, expect, vi, beforeEach } from "vitest";

// fix-member-delegation-keyless-banner (#4767, downstream half of #4761).
//
// The member-side BYOK resolvers must look up the delegation in the member's
// ACTIVE (current) workspace — the shared workspace the owner granted into —
// NOT the member's oldest workspace (MIN(created_at) = their pre-existing solo
// workspace). An invited member who already had a solo account holds two
// workspace_members rows; getDefaultWorkspaceForUser resolves the wrong (solo)
// one, so resolve_byok_key_owner / the byok_delegations SELECT find no row and
// the keyless "joiner" banner stays up.
//
// The fix swaps getDefaultWorkspaceForUser → resolveCurrentWorkspaceId in
// resolveByokDelegationContext (effective-key + pending) and in
// resolveKeyOwnerThenLease (runtime lease), so all three consumers query the
// shared workspace where the delegation actually lives.
//
// This test mocks BOTH workspace resolvers and primes the delegation row ONLY
// for the SHARED workspace. Pre-fix (uses getDefaultWorkspaceForUser → SOLO)
// every assertion fails; post-fix (uses resolveCurrentWorkspaceId → SHARED)
// they pass. The solo cases prove the own-key short-circuit + solo fallback are
// unaffected.

const {
  mockResolveCurrentWorkspaceId,
  mockGetDefaultWorkspaceForUser,
  mockIsByokDelegationsEnabled,
  mockServiceRpc,
  mockServiceFrom,
  mockReportSilentFallback,
  mockResolveGranteeAcceptanceStatus,
  mockRunWithByokLease,
} = vi.hoisted(() => ({
  mockResolveCurrentWorkspaceId: vi.fn(),
  mockGetDefaultWorkspaceForUser: vi.fn(),
  mockIsByokDelegationsEnabled: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockResolveGranteeAcceptanceStatus: vi.fn(),
  mockRunWithByokLease: vi.fn(),
}));

vi.mock("@/server/byok-lease", () => ({ runWithByokLease: mockRunWithByokLease }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ rpc: mockServiceRpc, from: mockServiceFrom })),
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ warn: vi.fn(), info: vi.fn(), error: vi.fn() }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: mockIsByokDelegationsEnabled,
  ANON_IDENTITY: { userId: "anon", role: "prd", orgId: null },
}));

// Both resolvers are mocked so the RED failure reflects the workspace-derivation
// distinction (solo vs shared), not a missing-export artifact.
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
  getDefaultWorkspaceForUser: mockGetDefaultWorkspaceForUser,
}));

vi.mock("@/server/byok-delegation-ui-resolver", () => ({
  resolveGranteeAcceptanceStatus: mockResolveGranteeAcceptanceStatus,
}));

import {
  userHasEffectiveByokKey,
  userHasPendingByokDelegation,
  resolveKeyOwnerThenLease,
} from "@/server/byok-resolver";

const MEMBER = "member-uuid";
const SOLO_WS = "member-uuid"; // workspaces.id == owner_user_id for the backfilled solo ws
const SHARED_WS = "shared-ws-uuid"; // the workspace the owner granted the delegation into
const GRANTOR = "grantor-uuid";

// Per-table dispatch for the service client `.from(table)` calls. The
// byok_delegations chain captures the workspace_id it is filtered on so we can
// return the grantee row ONLY for the shared workspace (the whole point).
let apiKeysResult: { data: unknown; error: unknown };
let workspaceOrgResult: { data: unknown; error: unknown };
let delegationRowByWorkspace: Record<string, { id: string } | null>;
let lastDelegationWorkspaceFilter: string | undefined;

function buildFrom() {
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      const chain = {
        select: () => chain,
        eq: () => chain,
        limit: () => Promise.resolve(apiKeysResult),
      };
      return chain;
    }
    if (table === "workspaces") {
      const chain = {
        select: () => chain,
        eq: () => chain,
        maybeSingle: () => Promise.resolve(workspaceOrgResult),
      };
      return chain;
    }
    if (table === "byok_delegations") {
      const chain = {
        select: () => chain,
        eq: (col: string, val: string) => {
          if (col === "workspace_id") lastDelegationWorkspaceFilter = val;
          return chain;
        },
        is: () => chain,
        maybeSingle: () =>
          Promise.resolve({
            data: delegationRowByWorkspace[lastDelegationWorkspaceFilter ?? ""] ?? null,
            error: null,
          }),
      };
      return chain;
    }
    throw new Error(`unexpected table ${table}`);
  });
}

// resolve_byok_key_owner: returns a delegation row ONLY when called with the
// shared workspace id. Pre-fix the resolver passes the solo workspace → no row.
function primeRpcSharedWorkspaceOnly(row: { key_owner_user_id: string; delegation_id: string }) {
  mockServiceRpc.mockImplementation((_fn: string, args: { p_workspace_id: string }) => ({
    maybeSingle: () =>
      Promise.resolve({
        data: args.p_workspace_id === SHARED_WS ? row : null,
        error: null,
      }),
  }));
}

let leasedKeyOwner: string | undefined;
let leasedDelegationId: string | undefined;

beforeEach(() => {
  vi.clearAllMocks();
  apiKeysResult = { data: [], error: null };
  workspaceOrgResult = { data: { organization_id: "org-1" }, error: null };
  delegationRowByWorkspace = {};
  lastDelegationWorkspaceFilter = undefined;
  leasedKeyOwner = undefined;
  leasedDelegationId = undefined;
  buildFrom();
  // The active (current) workspace is the SHARED one; the oldest workspace is
  // the SOLO one. The fix must use the former.
  mockResolveCurrentWorkspaceId.mockResolvedValue(SHARED_WS);
  mockGetDefaultWorkspaceForUser.mockResolvedValue(SOLO_WS);
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockServiceRpc.mockReturnValue({ maybeSingle: () => Promise.resolve({ data: null, error: null }) });
  mockResolveGranteeAcceptanceStatus.mockResolvedValue({
    accepted: true,
    withdrawn: false,
    sideLetterVersion: "v1",
    currentVersion: "v1",
  });
  mockRunWithByokLease.mockImplementation(
    (args: { keyOwnerUserId: string; delegationId?: string }) => {
      leasedKeyOwner = args.keyOwnerUserId;
      leasedDelegationId = args.delegationId;
      return Promise.resolve("ran");
    },
  );
});

describe("byok-resolver derives the CURRENT (shared) workspace, not the solo default", () => {
  test("userHasEffectiveByokKey queries the shared workspace and resolves true (accepted)", async () => {
    primeRpcSharedWorkspaceOnly({ key_owner_user_id: GRANTOR, delegation_id: "deleg-1" });
    const result = await userHasEffectiveByokKey(MEMBER, { onErrorReturn: false });
    expect(result).toBe(true);
    // Distinguishing assertion: the resolver must hand the RPC the SHARED ws.
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "resolve_byok_key_owner",
      expect.objectContaining({ p_workspace_id: SHARED_WS }),
    );
    expect(mockResolveCurrentWorkspaceId).toHaveBeenCalledWith(MEMBER, expect.anything());
    expect(mockGetDefaultWorkspaceForUser).not.toHaveBeenCalled();
  });

  test("shared+UNaccepted delegation → hasEffectiveKey false", async () => {
    // The mig-084 Gate-1 acceptance check lives inside the resolve_byok_key_owner
    // SQL RPC, which is mocked here — so at the TS layer an unaccepted grant is
    // indistinguishable from "no row" (both → RPC returns null → false). This
    // asserts the TS contract (null row → false); the SQL acceptance gate itself
    // is covered by the DB-backed byok integration suite, not this unit.
    const effective = await userHasEffectiveByokKey(MEMBER, { onErrorReturn: false });
    expect(effective).toBe(false);
  });

  test("shared+UNaccepted delegation → pending true (pending branch on the SHARED workspace)", async () => {
    // Pending check finds the grantee row in the SHARED workspace and the
    // acceptance status is not-current → pending true. This DOES exercise the
    // acceptance logic (via the resolveGranteeAcceptanceStatus mock), unlike the
    // effective-key half above.
    delegationRowByWorkspace[SHARED_WS] = { id: "deleg-1" };
    mockResolveGranteeAcceptanceStatus.mockResolvedValue({
      accepted: false,
      withdrawn: false,
      sideLetterVersion: null,
      currentVersion: "v1",
    });
    const pending = await userHasPendingByokDelegation(MEMBER);
    expect(pending).toBe(true);
    expect(lastDelegationWorkspaceFilter).toBe(SHARED_WS);
  });

  test("userHasPendingByokDelegation filters byok_delegations on the SHARED workspace", async () => {
    delegationRowByWorkspace[SHARED_WS] = { id: "deleg-1" };
    delegationRowByWorkspace[SOLO_WS] = null; // pre-fix would look here and find nothing
    mockResolveGranteeAcceptanceStatus.mockResolvedValue({
      accepted: false,
      withdrawn: false,
      sideLetterVersion: null,
      currentVersion: "v1",
    });
    const pending = await userHasPendingByokDelegation(MEMBER);
    expect(pending).toBe(true);
    expect(lastDelegationWorkspaceFilter).toBe(SHARED_WS);
    expect(mockGetDefaultWorkspaceForUser).not.toHaveBeenCalled();
  });

  test("resolveKeyOwnerThenLease opens the lease with the grantor key + delegationId for the active workspace", async () => {
    primeRpcSharedWorkspaceOnly({ key_owner_user_id: GRANTOR, delegation_id: "deleg-1" });
    await resolveKeyOwnerThenLease(MEMBER, MEMBER, async () => "x");
    expect(leasedKeyOwner).toBe(GRANTOR);
    expect(leasedDelegationId).toBe("deleg-1");
    expect(mockResolveCurrentWorkspaceId).toHaveBeenCalledWith(MEMBER, expect.anything());
  });

  test("own VALID key short-circuits before workspace derivation (solo unaffected)", async () => {
    apiKeysResult = { data: [{ id: "k1" }], error: null };
    expect(await userHasEffectiveByokKey(MEMBER, { onErrorReturn: false })).toBe(true);
    expect(mockResolveCurrentWorkspaceId).not.toHaveBeenCalled();
    expect(mockGetDefaultWorkspaceForUser).not.toHaveBeenCalled();
  });

  // Safety guard (NOT bug-reproduction): this asserts the degrade-to-solo
  // fallback is the safe direction. Because resolveCurrentWorkspaceId returns
  // the caller's own userId on a handled query error, and SOLO_WS === MEMBER by
  // construction, this passes identically pre- and post-fix — it is a
  // regression guard against a future change that would resolve a SIBLING
  // workspace on degrade, not a test that distinguishes the #4767 fix.
  test("degrade-to-solo safety guard: a degraded resolve queries the caller's own workspace, never a sibling", async () => {
    // On error resolveCurrentWorkspaceId Sentry-mirrors and returns the caller's
    // own userId (solo). The RPC then sees the solo ws, finds no delegation, and
    // the status endpoint stays fail-closed (false).
    mockResolveCurrentWorkspaceId.mockResolvedValue(MEMBER); // solo fallback
    primeRpcSharedWorkspaceOnly({ key_owner_user_id: GRANTOR, delegation_id: "deleg-1" });
    const result = await userHasEffectiveByokKey(MEMBER, { onErrorReturn: false });
    expect(result).toBe(false);
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "resolve_byok_key_owner",
      expect.objectContaining({ p_workspace_id: MEMBER }),
    );
  });
});
