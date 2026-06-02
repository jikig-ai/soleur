import { describe, test, expect, vi, beforeEach } from "vitest";

// AC12 (feat-byok-delegation-consent, #4625): on ANY resolver fall-through
// branch (workspace degrade-to-solo, flag disabled, RPC error, no delegation
// row), resolveKeyOwnerThenLease MUST lease the CALLER's own key —
// keyOwnerUserId === callerUserId — never a grantor key. The lease body then
// raises MissingByokKeyError for a keyless grantee (fail-CLOSED), which is the
// desired UX. This guards the deepen P0 #3 invariant: no error path ever leases
// a grantor key.
//
// #4767: the workspace source is now resolveCurrentWorkspaceId (active
// workspace), which NEVER throws — on a query error it Sentry-mirrors and
// returns the caller's own solo workspace (never a sibling). The fail-closed
// scenario is therefore "resolver degrades to the solo workspace → no
// delegation found there → caller key leased", not an injected throw. The
// outer try/catch in resolveKeyOwnerThenLease survives as a defensive guard
// (covered by its own test below).

const {
  mockRunWithByokLease,
  mockResolveCurrentWorkspaceId,
  mockIsByokDelegationsEnabled,
  mockServiceRpc,
  mockServiceFrom,
} = vi.hoisted(() => ({
  mockRunWithByokLease: vi.fn(),
  mockResolveCurrentWorkspaceId: vi.fn(),
  mockIsByokDelegationsEnabled: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockServiceFrom: vi.fn(),
}));

vi.mock("@/server/byok-lease", () => ({
  runWithByokLease: mockRunWithByokLease,
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ rpc: mockServiceRpc, from: mockServiceFrom })),
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ warn: vi.fn(), info: vi.fn(), error: vi.fn() }),
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: mockIsByokDelegationsEnabled,
  ANON_IDENTITY: { userId: "anon", role: "prd", orgId: null },
}));

vi.mock("../../server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

import { resolveKeyOwnerThenLease } from "@/server/byok-resolver";

const CALLER = "caller-uuid";
const WORKSPACE_CTX = "caller-uuid";
const GRANTOR = "grantor-uuid";

// resolveOrgIdForWorkspace -> service.from("workspaces").select().eq().maybeSingle()
function primeWorkspaceOrgLookup(orgId: string | null) {
  mockServiceFrom.mockReturnValue({
    select: () => ({
      eq: () => ({
        maybeSingle: () => Promise.resolve({ data: orgId ? { organization_id: orgId } : null, error: null }),
      }),
    }),
  });
}

// service.rpc("resolve_byok_key_owner", ...).maybeSingle()
function primeResolverRpc(result: { data: unknown; error: unknown }) {
  mockServiceRpc.mockReturnValue({ maybeSingle: () => Promise.resolve(result) });
}

let leasedKeyOwner: string | undefined;
let leasedDelegationId: string | undefined;

beforeEach(() => {
  vi.clearAllMocks();
  leasedKeyOwner = undefined;
  leasedDelegationId = undefined;
  mockRunWithByokLease.mockImplementation((args: { keyOwnerUserId: string; delegationId?: string }) => {
    leasedKeyOwner = args.keyOwnerUserId;
    leasedDelegationId = args.delegationId;
    return Promise.resolve("ran");
  });
  primeWorkspaceOrgLookup("org-1");
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
});

describe("resolveKeyOwnerThenLease — fail-closed on every error branch (AC12)", () => {
  test("workspace resolver degrades to solo workspace → leases caller key, no delegationId", async () => {
    // resolveCurrentWorkspaceId never throws; on a query error it returns the
    // caller's own (solo) workspace. The RPC then finds no delegation there →
    // caller key leased, fail-closed.
    mockResolveCurrentWorkspaceId.mockResolvedValue(WORKSPACE_CTX);
    primeResolverRpc({ data: null, error: null });
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(CALLER);
    expect(leasedDelegationId).toBeUndefined();
  });

  test("defensive: workspace resolver unexpectedly throws → outer catch leases caller key", async () => {
    // resolveCurrentWorkspaceId is documented never-throw, but the defensive
    // try/catch must still fall to the direct (caller-key) lease if it ever does.
    mockResolveCurrentWorkspaceId.mockRejectedValue(new Error("unexpected"));
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(CALLER);
    expect(leasedDelegationId).toBeUndefined();
  });

  test("flag disabled → leases caller key", async () => {
    mockResolveCurrentWorkspaceId.mockResolvedValue("ws-1");
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(CALLER);
    expect(leasedDelegationId).toBeUndefined();
  });

  test("RPC error → leases caller key (never the grantor)", async () => {
    mockResolveCurrentWorkspaceId.mockResolvedValue("ws-1");
    primeResolverRpc({ data: null, error: { message: "rpc boom" } });
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(CALLER);
    expect(leasedKeyOwner).not.toBe(GRANTOR);
    expect(leasedDelegationId).toBeUndefined();
  });

  test("no delegation row → leases caller key (MissingByokKeyError UX)", async () => {
    mockResolveCurrentWorkspaceId.mockResolvedValue("ws-1");
    primeResolverRpc({ data: null, error: null });
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(CALLER);
    expect(leasedDelegationId).toBeUndefined();
  });

  test("happy path (gated delegation resolves) DOES lease the grantor key", async () => {
    // Negative control: proves the test can distinguish the grantor-lease
    // path from the fail-closed path (so the assertions above aren't vacuous).
    mockResolveCurrentWorkspaceId.mockResolvedValue("ws-1");
    primeResolverRpc({ data: { key_owner_user_id: GRANTOR, delegation_id: "deleg-1" }, error: null });
    await resolveKeyOwnerThenLease(CALLER, WORKSPACE_CTX, async () => "x");
    expect(leasedKeyOwner).toBe(GRANTOR);
    expect(leasedDelegationId).toBe("deleg-1");
  });
});
