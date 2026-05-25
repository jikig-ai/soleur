import { describe, test, expect, vi, beforeEach } from "vitest";

// #4390 — account-delete cascade Sentry mirror.
//
// Asserts every FATAL anonymise step (3.82-3.93 excluding 3.86) AND the
// terminal auth-delete failure route through `reportSilentFallback`, and
// the non-fatal 3.86 step routes through `warnSilentFallback`. Pinned by
// op-slug + feature-tag so the dashboard can key per-stage alerts.
//
// Mocking strategy: mock `@/server/observability` directly (NOT
// `@sentry/nextjs`). Repo precedent: api-accept-terms-ledger.test.ts
// asserts on helper input args rather than re-testing the helper's
// internal pseudonymisation, which lives in observability.test.ts.

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

interface StageCase {
  stage: string;
  rpc: string | null; // null = auth.admin.deleteUser failure
  warn: boolean; // true = expect warnSilentFallback, false = reportSilentFallback
  messageContains: string;
}

const STAGES: StageCase[] = [
  {
    stage: "anonymise-action-sends",
    rpc: "anonymise_action_sends",
    warn: false,
    messageContains: "anonymise_action_sends",
  },
  {
    stage: "anonymise-template-authorizations",
    rpc: "anonymise_template_authorizations",
    warn: false,
    messageContains: "anonymise_template_authorizations",
  },
  {
    stage: "anonymise-scope-grants",
    rpc: "anonymise_scope_grants",
    warn: false,
    messageContains: "anonymise_scope_grants",
  },
  {
    stage: "anonymise-tc-acceptances",
    rpc: "anonymise_tc_acceptances",
    warn: false,
    messageContains: "anonymise_tc_acceptances",
  },
  {
    stage: "anonymise-audit-github-token-use",
    rpc: "anonymise_audit_github_token_use",
    warn: true,
    messageContains: "anonymise_audit_github_token_use",
  },
  {
    stage: "anonymise-workspace-member-attestations",
    rpc: "anonymise_workspace_member_attestations",
    warn: false,
    messageContains: "anonymise_workspace_member_attestations",
  },
  {
    stage: "anonymise-workspace-member-removals",
    rpc: "anonymise_workspace_member_removals",
    warn: false,
    messageContains: "anonymise_workspace_member_removals",
  },
  {
    stage: "anonymise-workspace-members",
    rpc: "anonymise_workspace_members",
    warn: false,
    messageContains: "anonymise_workspace_members",
  },
  {
    stage: "anonymise-organization-membership",
    rpc: "anonymise_organization_membership",
    warn: false,
    messageContains: "anonymise_organization_membership",
  },
  {
    stage: "anonymise-workspace-member-actions",
    rpc: "anonymise_workspace_member_actions",
    warn: false,
    messageContains: "anonymise_workspace_member_actions",
  },
  {
    stage: "auth-delete",
    rpc: null,
    warn: false,
    messageContains: "Failed to delete auth record",
  },
];

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

describe("deleteAccount Sentry mirror (#4390)", () => {
  test.each(STAGES)(
    "$stage failure routes through correct helper with feature+op tags",
    async ({ stage, rpc, warn, messageContains }) => {
      if (rpc === null) {
        // auth-delete failure: every RPC OK, mockDeleteUser fails.
        mockRpc.mockResolvedValue({ error: null });
        mockDeleteUser.mockResolvedValueOnce({
          error: { message: "synthetic_auth_delete_error" },
        });
      } else {
        mockRpc.mockImplementation(async (name: string) => {
          if (name === rpc) {
            return { error: { message: `synthetic_${rpc}_error` } };
          }
          return { error: null };
        });
      }

      const result = await deleteAccount(USER_ID, USER_EMAIL);

      const expectedMatcher = expect.objectContaining({
        feature: "account-delete",
        op: stage,
        message: expect.stringContaining(messageContains),
        extra: expect.objectContaining({ userId: USER_ID }),
      });

      if (warn) {
        // 3.86 is non-fatal — warnSilentFallback fires, cascade continues to
        // auth-delete (which succeeds with the default mockDeleteUser).
        expect(mockWarnSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expectedMatcher,
        );
        expect(mockReportSilentFallback).not.toHaveBeenCalled();
        expect(result.success).toBe(true);
      } else {
        // FATAL: reportSilentFallback fires, cascade short-circuits.
        expect(mockReportSilentFallback).toHaveBeenCalledWith(
          expect.anything(),
          expectedMatcher,
        );
        expect(mockWarnSilentFallback).not.toHaveBeenCalled();
        expect(result.success).toBe(false);
        expect(result.error).toBe(
          "Account deletion failed. Please try again.",
        );
      }
    },
  );

  test("happy path: all RPCs + auth-delete succeed, neither helper fires", async () => {
    mockRpc.mockResolvedValue({ error: null });

    const result = await deleteAccount(USER_ID, USER_EMAIL);

    expect(result).toEqual({ success: true });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    expect(mockWarnSilentFallback).not.toHaveBeenCalled();
  });
});
