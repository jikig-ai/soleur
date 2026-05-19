import { describe, test, expect, vi, beforeEach } from "vitest";

// PR-G (#3947) Phase 9.3 / AC5 — account-delete cascade ordering.
//
// Contract under test (server/account-delete.ts):
//   The destructive cascade calls these RPCs in this fixed order BEFORE
//   auth.admin.deleteUser fires:
//     1. anonymise_dsar_export_audit_pii  (non-fatal — logs and continues)
//     2. anonymise_scope_grants           (FATAL — aborts on failure;     PR-G NEW)
//     3. anonymise_tc_acceptances         (FATAL — aborts on failure)
//     4. auth.admin.deleteUser            (FATAL — aborts on failure)
//
//   The ordering is load-bearing: FKs on public.users(id) for both
//   scope_grants and tc_acceptances are ON DELETE RESTRICT, so skipping
//   either anonymise step would leave the auth.admin.deleteUser call
//   unable to cascade. anonymise_scope_grants MUST run BEFORE
//   anonymise_tc_acceptances per plan rev-2 to match FK order.
//
// Test cases (all run against a vi.mock'd service client — no DB):
//   1. Happy path: all RPCs OK + auth-delete OK → success.
//      Assert RPC sequence + auth.admin.deleteUser fires LAST with the
//      provided userId.
//   2. anonymise_scope_grants returns { error } → cascade aborts.
//      auth.admin.deleteUser NOT called. anonymise_tc_acceptances NOT
//      called. Result is { success: false, error: ... }.
//   3. anonymise_scope_grants throws → cascade aborts (same as case 2).

const {
  callOrder,
  mockRpc,
  mockGetUserById,
  mockDeleteUser,
  mockStorageList,
  mockStorageRemove,
  mockTableUpdate,
  mockLogger,
  mockAbortAllUserSessions,
  mockDeleteWorkspace,
} = vi.hoisted(() => {
  const callOrder: string[] = [];
  return {
    callOrder,
    mockRpc: vi.fn(),
    mockGetUserById: vi.fn(),
    mockDeleteUser: vi.fn(),
    mockStorageList: vi.fn(),
    mockStorageRemove: vi.fn(),
    mockTableUpdate: vi.fn(),
    mockLogger: {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    },
    mockAbortAllUserSessions: vi.fn(),
    mockDeleteWorkspace: vi.fn(),
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    auth: {
      admin: {
        getUserById: mockGetUserById,
        deleteUser: (userId: string) => {
          callOrder.push("auth.admin.deleteUser");
          return mockDeleteUser(userId);
        },
      },
    },
    rpc: (name: string, args: unknown) => {
      callOrder.push(name);
      return mockRpc(name, args);
    },
    from: (_table: string) => ({
      // dsar_export_jobs.update().eq().in() chain in step 1.5
      update: (_patch: unknown) => ({
        eq: (_col: string, _val: unknown) => ({
          in: (_col2: string, _vals: unknown[]) => mockTableUpdate(),
        }),
      }),
    }),
    storage: {
      from: (_bucket: string) => ({
        list: (_folder: string, _opts: unknown) => mockStorageList(),
        remove: (_paths: string[]) => mockStorageRemove(),
      }),
    },
  }),
}));

vi.mock("@/server/agent-runner", () => ({
  abortAllUserSessions: mockAbortAllUserSessions,
}));

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace,
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

// Module-under-test must be imported AFTER vi.mock declarations are
// hoisted but the alias resolution happens at import-time, so this is
// a top-level import — vitest hoists vi.mock above it.
import { deleteAccount } from "@/server/account-delete";

const USER_ID = "test-user-uuid";
const USER_EMAIL = "founder@example.com";

beforeEach(() => {
  callOrder.length = 0;
  vi.clearAllMocks();

  // Default: user lookup succeeds with matching email.
  mockGetUserById.mockResolvedValue({
    data: { user: { id: USER_ID, email: USER_EMAIL } },
    error: null,
  });
  // Default: dsar_export_jobs abort succeeds.
  mockTableUpdate.mockResolvedValue({ data: null, error: null });
  // Default: storage list returns empty (no blobs to purge).
  mockStorageList.mockResolvedValue({ data: [], error: null });
  mockStorageRemove.mockResolvedValue({ data: null, error: null });
  // Default: auth-delete succeeds.
  mockDeleteUser.mockResolvedValue({ error: null });
});

describe("deleteAccount cascade ordering (PR-G AC5)", () => {
  test("happy path: all RPCs succeed → success, scope_grants BEFORE tc_acceptances, auth-delete LAST", async () => {
    // Every RPC returns { error: null }.
    mockRpc.mockResolvedValue({ error: null });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result).toEqual({ success: true });

    // All three anonymise RPCs were called exactly once.
    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_dsar_export_audit_pii");
    expect(rpcNames).toContain("anonymise_scope_grants");
    expect(rpcNames).toContain("anonymise_tc_acceptances");
    expect(
      rpcNames.filter((n) => n === "anonymise_scope_grants").length,
    ).toBe(1);
    expect(
      rpcNames.filter((n) => n === "anonymise_tc_acceptances").length,
    ).toBe(1);

    // auth.admin.deleteUser fired with the right userId.
    expect(mockDeleteUser).toHaveBeenCalledTimes(1);
    expect(mockDeleteUser).toHaveBeenCalledWith(USER_ID);

    // Ordering invariants (the load-bearing assertion for AC5):
    const idxScope = callOrder.indexOf("anonymise_scope_grants");
    const idxTc = callOrder.indexOf("anonymise_tc_acceptances");
    const idxAuth = callOrder.indexOf("auth.admin.deleteUser");
    expect(idxScope).toBeGreaterThanOrEqual(0);
    expect(idxTc).toBeGreaterThanOrEqual(0);
    expect(idxAuth).toBeGreaterThanOrEqual(0);
    expect(idxScope).toBeLessThan(idxTc);
    expect(idxTc).toBeLessThan(idxAuth);

    // auth.admin.deleteUser is the LAST tracked step in the cascade.
    expect(callOrder[callOrder.length - 1]).toBe("auth.admin.deleteUser");
  });

  test("anonymise_scope_grants returns { error } → cascade aborts, auth-delete and tc_acceptances NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_scope_grants") {
        return { error: { message: "synthetic_rpc_error" } };
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    // tc_acceptances was NEVER called — cascade aborted at scope_grants.
    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_scope_grants");
    expect(rpcNames).not.toContain("anonymise_tc_acceptances");

    // auth.admin.deleteUser was NEVER called.
    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.admin.deleteUser");
    expect(callOrder).not.toContain("anonymise_tc_acceptances");
  });

  test("anonymise_scope_grants throws → cascade aborts, auth-delete and tc_acceptances NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_scope_grants") {
        throw new Error("synthetic_rpc_throw");
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_scope_grants");
    expect(rpcNames).not.toContain("anonymise_tc_acceptances");

    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.admin.deleteUser");
    expect(callOrder).not.toContain("anonymise_tc_acceptances");
  });
});
