import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-skip-api-key-onboarding (#4642, PR #4640) — AC2.
//
// userHasEffectiveByokKey resolves whether a user has a USABLE key for the
// onboarding redirect gates: an own VALID anthropic key OR an active,
// accepted BYOK delegation. Usability ≠ presence: an own *invalid* key must
// NOT count (it would route the user past /setup-key into a chat dead-end).
//
//   own VALID anthropic key   → true  (flag on OR off — short-circuits)
//   own INVALID/non-anthropic → false (routed to /setup-key, preserved)
//   accepted delegation       → true  (flag on; delegation_id != null)
//   granted-not-accepted      → false (resolver gate returns no row)
//   truly keyless             → false (flag on)
//   resolution error          → opts.onErrorReturn, with a Sentry mirror
//
// userHasPendingByokDelegation is the banner's "you have a grant — accept it"
// signal: a non-revoked grantee delegation with no current-version acceptance.

const {
  mockResolveCurrentWorkspaceId,
  mockIsByokDelegationsEnabled,
  mockServiceRpc,
  mockServiceFrom,
  mockReportSilentFallback,
  mockResolveGranteeAcceptanceStatus,
} = vi.hoisted(() => ({
  mockResolveCurrentWorkspaceId: vi.fn(),
  mockIsByokDelegationsEnabled: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockResolveGranteeAcceptanceStatus: vi.fn(),
}));

vi.mock("@/server/byok-lease", () => ({ runWithByokLease: vi.fn() }));

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

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

vi.mock("@/server/byok-delegation-ui-resolver", () => ({
  resolveGranteeAcceptanceStatus: mockResolveGranteeAcceptanceStatus,
}));

import {
  userHasEffectiveByokKey,
  userHasPendingByokDelegation,
} from "@/server/byok-resolver";

const CALLER = "caller-uuid";
const WORKSPACE = "ws-1";

// Per-table dispatch for the service client `.from(table)` calls.
let apiKeysResult: { data: unknown; error: unknown };
let workspaceOrgResult: { data: unknown; error: unknown };
let delegationRowResult: { data: unknown; error: unknown };

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
        eq: () => chain,
        is: () => chain,
        maybeSingle: () => Promise.resolve(delegationRowResult),
      };
      return chain;
    }
    throw new Error(`unexpected table ${table}`);
  });
}

function primeRpc(result: { data: unknown; error: unknown }) {
  mockServiceRpc.mockReturnValue({ maybeSingle: () => Promise.resolve(result) });
}

beforeEach(() => {
  vi.clearAllMocks();
  apiKeysResult = { data: [], error: null };
  workspaceOrgResult = { data: { organization_id: "org-1" }, error: null };
  delegationRowResult = { data: null, error: null };
  buildFrom();
  mockResolveCurrentWorkspaceId.mockResolvedValue(WORKSPACE);
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  primeRpc({ data: null, error: null });
});

describe("userHasEffectiveByokKey (AC2)", () => {
  test("own VALID anthropic key → true (flag ON)", async () => {
    apiKeysResult = { data: [{ id: "k1" }], error: null };
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(true);
  });

  test("own VALID anthropic key → true even when delegations flag is OFF", async () => {
    apiKeysResult = { data: [{ id: "k1" }], error: null };
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(true);
    // Own-valid-key short-circuits BEFORE any workspace/flag resolution.
    expect(mockResolveCurrentWorkspaceId).not.toHaveBeenCalled();
  });

  test("own INVALID/non-anthropic key only → false (routed to /setup-key)", async () => {
    // is_valid=true filter yields no row; the RPC's UNFILTERED own-key
    // short-circuit returns (caller, null) — must NOT count as effective.
    apiKeysResult = { data: [], error: null };
    primeRpc({ data: { key_owner_user_id: CALLER, delegation_id: null }, error: null });
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(false);
  });

  test("active accepted delegation (no own key) → true", async () => {
    apiKeysResult = { data: [], error: null };
    primeRpc({ data: { key_owner_user_id: "grantor-uuid", delegation_id: "deleg-1" }, error: null });
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(true);
  });

  test("granted-not-accepted delegation → false (resolver returns no row)", async () => {
    apiKeysResult = { data: [], error: null };
    primeRpc({ data: null, error: null });
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(false);
  });

  test("truly keyless, flag ON → false", async () => {
    apiKeysResult = { data: [], error: null };
    primeRpc({ data: null, error: null });
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(false);
  });

  test("keyless, flag OFF → false (no delegation path)", async () => {
    apiKeysResult = { data: [], error: null };
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(false);
  });

  test("uses the SAME resolveCurrentWorkspaceId (active workspace) the lease uses (parity)", async () => {
    apiKeysResult = { data: [], error: null };
    primeRpc({ data: { key_owner_user_id: "g", delegation_id: "d" }, error: null });
    await userHasEffectiveByokKey(CALLER, { onErrorReturn: true });
    expect(mockResolveCurrentWorkspaceId).toHaveBeenCalledWith(CALLER, expect.anything());
  });

  test("resolution error → onErrorReturn (fail-open) + Sentry mirror", async () => {
    apiKeysResult = { data: [], error: null };
    mockResolveCurrentWorkspaceId.mockRejectedValue(new Error("workspace boom"));
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: true })).toBe(true);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("resolution error → onErrorReturn (fail-closed for status endpoint)", async () => {
    apiKeysResult = { data: [], error: null };
    mockResolveCurrentWorkspaceId.mockRejectedValue(new Error("workspace boom"));
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: false })).toBe(false);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });

  test("api_keys query error → treated as error path (onErrorReturn) + mirror", async () => {
    apiKeysResult = { data: null, error: { message: "db boom" } };
    expect(await userHasEffectiveByokKey(CALLER, { onErrorReturn: false })).toBe(false);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});

describe("userHasPendingByokDelegation (banner accept-grant branch)", () => {
  test("non-revoked grantee delegation, not accepted → true", async () => {
    delegationRowResult = { data: { id: "deleg-1" }, error: null };
    mockResolveGranteeAcceptanceStatus.mockResolvedValue({
      accepted: false,
      withdrawn: false,
      sideLetterVersion: null,
      currentVersion: "v1",
    });
    expect(await userHasPendingByokDelegation(CALLER)).toBe(true);
  });

  test("delegation accepted at current version → false", async () => {
    delegationRowResult = { data: { id: "deleg-1" }, error: null };
    mockResolveGranteeAcceptanceStatus.mockResolvedValue({
      accepted: true,
      withdrawn: false,
      sideLetterVersion: "v1",
      currentVersion: "v1",
    });
    expect(await userHasPendingByokDelegation(CALLER)).toBe(false);
  });

  test("delegation accepted but withdrawn → true (re-accept needed)", async () => {
    delegationRowResult = { data: { id: "deleg-1" }, error: null };
    mockResolveGranteeAcceptanceStatus.mockResolvedValue({
      accepted: true,
      withdrawn: true,
      sideLetterVersion: "v1",
      currentVersion: "v1",
    });
    expect(await userHasPendingByokDelegation(CALLER)).toBe(true);
  });

  test("no grantee delegation row → false", async () => {
    delegationRowResult = { data: null, error: null };
    expect(await userHasPendingByokDelegation(CALLER)).toBe(false);
  });

  test("delegations flag OFF → false (no query)", async () => {
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    expect(await userHasPendingByokDelegation(CALLER)).toBe(false);
  });

  test("error path → false + Sentry mirror", async () => {
    mockResolveCurrentWorkspaceId.mockRejectedValue(new Error("boom"));
    expect(await userHasPendingByokDelegation(CALLER)).toBe(false);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
