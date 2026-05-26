import { describe, test, expect, vi, beforeEach } from "vitest";

// PR-I (#4078) Phase 9.4 — account-delete cascade with template_authorizations.
//
// Asserts the cascade now calls FIVE anonymise RPCs in this fixed order
// BEFORE auth.admin.deleteUser fires:
//   1. anonymise_dsar_export_audit_pii  (non-fatal)
//   2. anonymise_action_sends           (FATAL on failure)
//   3. anonymise_template_authorizations (FATAL on failure)   PR-I NEW
//   4. anonymise_scope_grants           (FATAL on failure)
//   5. anonymise_tc_acceptances         (FATAL on failure)
//   6. auth.admin.deleteUser            (FATAL on failure)
//
// The ordering is SEMANTIC, not FK-driven (plan §Phase 8): `anonymise_*`
// performs UPDATE, not DELETE, so the scope_grants FK ON DELETE RESTRICT
// does not fire. The required invariant is: `dsr_erasure` MUST be set on
// child template_authorizations rows BEFORE the parent scope_grant's
// user_id is nulled — otherwise the audit-trail attribution (Art. 5(2))
// breaks. This test is the load-bearing TR7 gate.
//
// Mirrors test/server/scope-grants/account-delete-scope-grants-cascade.test.ts
// (PR-G AC5) — vi.mock'd service client; no DB.

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
  mockReportSilentFallback,
  mockWarnSilentFallback,
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
    mockReportSilentFallback: vi.fn(),
    mockWarnSilentFallback: vi.fn(),
  };
});

vi.mock("@/lib/supabase/service", () => ({
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
      update: (_patch: unknown) => ({
        eq: (_col: string, _val: unknown) => ({
          in: (_col2: string, _vals: unknown[]) => mockTableUpdate(),
        }),
      }),
      // mig 068 #4318 step 3.901 ordering-guard probe.
      select: (_cols: string, _opts?: unknown) => ({
        eq: (_col: string, _val: unknown) =>
          Promise.resolve({ count: 1, data: null, error: null }),
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

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  hashUserId: (id: string) => `hash:${id}`,
}));

import { deleteAccount } from "@/server/account-delete";

const USER_ID = "test-user-uuid";
const USER_EMAIL = "founder@example.com";

beforeEach(() => {
  callOrder.length = 0;
  vi.clearAllMocks();
  mockGetUserById.mockResolvedValue({
    data: { user: { id: USER_ID, email: USER_EMAIL } },
    error: null,
  });
  mockTableUpdate.mockResolvedValue({ data: null, error: null });
  mockStorageList.mockResolvedValue({ data: [], error: null });
  mockStorageRemove.mockResolvedValue({ data: null, error: null });
  mockDeleteUser.mockResolvedValue({ error: null });
});

describe("deleteAccount cascade ordering with template_authorizations (PR-I TR7)", () => {
  test("happy path: all anonymise RPCs succeed, template_authorizations runs BETWEEN action_sends and scope_grants", async () => {
    mockRpc.mockResolvedValue({ error: null });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result).toEqual({ success: true });

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_action_sends");
    expect(rpcNames).toContain("anonymise_template_authorizations");
    expect(rpcNames).toContain("anonymise_scope_grants");
    expect(rpcNames).toContain("anonymise_tc_acceptances");

    // Exactly once each — no retries / duplicates.
    expect(
      rpcNames.filter((n) => n === "anonymise_template_authorizations").length,
    ).toBe(1);

    // SEMANTIC ordering invariant (Art. 5(2) attribution):
    //   action_sends < template_authorizations < scope_grants < tc_acceptances < auth-delete.
    const idxAS = callOrder.indexOf("anonymise_action_sends");
    const idxTA = callOrder.indexOf("anonymise_template_authorizations");
    const idxSG = callOrder.indexOf("anonymise_scope_grants");
    const idxTC = callOrder.indexOf("anonymise_tc_acceptances");
    const idxAuth = callOrder.indexOf("auth.admin.deleteUser");

    expect(idxAS).toBeGreaterThanOrEqual(0);
    expect(idxTA).toBeGreaterThanOrEqual(0);
    expect(idxSG).toBeGreaterThanOrEqual(0);
    expect(idxTC).toBeGreaterThanOrEqual(0);
    expect(idxAuth).toBeGreaterThanOrEqual(0);

    expect(idxAS).toBeLessThan(idxTA);
    expect(idxTA).toBeLessThan(idxSG);
    expect(idxSG).toBeLessThan(idxTC);
    expect(idxTC).toBeLessThan(idxAuth);

    expect(callOrder[callOrder.length - 1]).toBe("auth.admin.deleteUser");
  });

  test("anonymise_template_authorizations returns { error } → cascade aborts, scope_grants/tc/auth NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_template_authorizations") {
        return { error: { message: "synthetic_template_rpc_error" } };
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_template_authorizations");
    expect(rpcNames).not.toContain("anonymise_scope_grants");
    expect(rpcNames).not.toContain("anonymise_tc_acceptances");

    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.admin.deleteUser");

    // Sentry mirror — failure routes through reportSilentFallback helper
    // (ADR-029 boundary: helper pseudonymises extra.userId before emit).
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "account-delete",
        op: "anonymise-template-authorizations",
        message: expect.stringContaining("anonymise_template_authorizations"),
        extra: expect.objectContaining({ userId: USER_ID }),
      }),
    );
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  test("anonymise_template_authorizations throws → cascade aborts, scope_grants/tc/auth NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_template_authorizations") {
        throw new Error("synthetic_template_rpc_throw");
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_template_authorizations");
    expect(rpcNames).not.toContain("anonymise_scope_grants");
    expect(mockDeleteUser).not.toHaveBeenCalled();

    // Sentry mirror — throw path routes through reportSilentFallback helper.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "account-delete",
        op: "anonymise-template-authorizations",
        message: expect.stringContaining("anonymise_template_authorizations"),
        extra: expect.objectContaining({ userId: USER_ID }),
      }),
    );
  });
});
