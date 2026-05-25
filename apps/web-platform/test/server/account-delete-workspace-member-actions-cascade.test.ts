import { describe, test, expect, vi, beforeEach } from "vitest";

// feat-workspace-member-actions-audit (#4231) — account-delete cascade with
// workspace_member_actions audit log.
//
// Asserts the cascade calls `anonymise_workspace_member_actions` AFTER
// `anonymise_organization_membership` and BEFORE `auth.admin.deleteUser`.
// Failure of the RPC is FATAL (the audit row's PII would survive the
// auth-delete cascade since public.users FK is RESTRICT, blocking the
// cascade entirely; better to fail loud than to leave orphan PII).
//
// Mirrors test/server/account-delete-template-authorizations-cascade.test.ts
// (PR-I TR7) and test/server/scope-grants/account-delete-scope-grants-cascade.test.ts
// (PR-G AC5).

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

describe("deleteAccount cascade ordering with workspace_member_actions (#4231)", () => {
  test("happy path: anonymise_workspace_member_actions runs BETWEEN anonymise_organization_membership and auth.admin.deleteUser", async () => {
    mockRpc.mockResolvedValue({ error: null });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result).toEqual({ success: true });

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_organization_membership");
    expect(rpcNames).toContain("anonymise_workspace_member_actions");

    // Exactly once — no retries / duplicates.
    expect(
      rpcNames.filter((n) => n === "anonymise_workspace_member_actions").length,
    ).toBe(1);

    // ORDERING invariant: 3.92 < 3.93 < 4 (auth-delete).
    const idxOrg = callOrder.indexOf("anonymise_organization_membership");
    const idxAudit = callOrder.indexOf("anonymise_workspace_member_actions");
    const idxAuth = callOrder.indexOf("auth.admin.deleteUser");

    expect(idxOrg).toBeGreaterThanOrEqual(0);
    expect(idxAudit).toBeGreaterThanOrEqual(0);
    expect(idxAuth).toBeGreaterThanOrEqual(0);

    expect(idxOrg).toBeLessThan(idxAudit);
    expect(idxAudit).toBeLessThan(idxAuth);

    expect(callOrder[callOrder.length - 1]).toBe("auth.admin.deleteUser");
  });

  test("called with the correct p_user_id arg", async () => {
    mockRpc.mockResolvedValue({ error: null });

    await deleteAccount(USER_ID, USER_EMAIL);

    const auditCall = mockRpc.mock.calls.find(
      (c) => c[0] === "anonymise_workspace_member_actions",
    );
    expect(auditCall).toBeDefined();
    expect(auditCall![1]).toEqual({ p_user_id: USER_ID });
  });

  test("anonymise_workspace_member_actions returns { error } → cascade aborts, auth-delete NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_workspace_member_actions") {
        return { error: { message: "synthetic_audit_rpc_error" } };
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    const rpcNames = mockRpc.mock.calls.map((c) => c[0] as string);
    expect(rpcNames).toContain("anonymise_workspace_member_actions");

    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.admin.deleteUser");

    // Sentry mirror — failure routes through reportSilentFallback helper.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "account-delete",
        op: "anonymise-workspace-member-actions",
        message: expect.stringContaining("anonymise_workspace_member_actions"),
        extra: expect.objectContaining({ userId: USER_ID }),
      }),
    );
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });

  test("anonymise_workspace_member_actions throws → cascade aborts, auth-delete NOT called", async () => {
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_workspace_member_actions") {
        throw new Error("synthetic_audit_rpc_throw");
      }
      return { error: null };
    });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result.success).toBe(false);
    expect(result.error).toBeTruthy();

    expect(mockDeleteUser).not.toHaveBeenCalled();
    expect(callOrder).not.toContain("auth.admin.deleteUser");

    // Sentry mirror — throw path routes through reportSilentFallback helper.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "account-delete",
        op: "anonymise-workspace-member-actions",
        message: expect.stringContaining("anonymise_workspace_member_actions"),
        extra: expect.objectContaining({ userId: USER_ID }),
      }),
    );
  });
});
