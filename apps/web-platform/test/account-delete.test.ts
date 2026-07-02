import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { SlidingWindowCounter } from "../server/rate-limiter";

// ---------------------------------------------------------------------------
// Mock Supabase service client — must be defined before importing the module
// ---------------------------------------------------------------------------

const mockFrom = vi.fn();
const mockRpc = vi.fn();
const mockAuth = {
  admin: {
    getUserById: vi.fn(),
    deleteUser: vi.fn(),
  },
};
const mockStorageList = vi.fn();
const mockStorageRemove = vi.fn();
const mockStorageFrom = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    rpc: mockRpc,
    auth: mockAuth,
    storage: { from: mockStorageFrom },
  }),
}));

// Mock agent-runner abortAllUserSessions
const mockAbortAllUserSessions = vi.fn();
vi.mock("@/server/agent-runner", () => ({
  abortAllUserSessions: (...args: unknown[]) => mockAbortAllUserSessions(...args),
}));

// Mock workspace deletion
const mockDeleteWorkspace = vi.fn();
vi.mock("@/server/workspace", () => ({
  deleteWorkspace: (...args: unknown[]) => mockDeleteWorkspace(...args),
}));

// Art. 17 erasure of the shared git-data bare repo (#5274 Sub-PR 3.D, DL-1/AC9).
// account-delete imports ONLY removeGitDataRepo from this module, so a wholesale
// factory is safe (nothing else in the SUT graph reads its other exports).
const mockRemoveGitDataRepo = vi.fn();
vi.mock("@/server/git-data-replication", () => ({
  removeGitDataRepo: (...args: unknown[]) => mockRemoveGitDataRepo(...args),
}));

// ---------------------------------------------------------------------------
// Import the module under test
// ---------------------------------------------------------------------------

import { deleteAccount } from "../server/account-delete";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseMocks(overrides: {
  user?: { id: string; email: string } | null;
  getUserError?: { message: string };
  deleteAuthError?: { message: string } | null;
} = {}) {
  const user = overrides.user ?? { id: "user-123", email: "test@example.com" };

  mockAuth.admin.getUserById.mockResolvedValue(
    overrides.getUserError
      ? { data: { user: null }, error: overrides.getUserError }
      : { data: { user }, error: null },
  );

  mockAuth.admin.deleteUser.mockResolvedValue({
    data: {},
    error: overrides.deleteAuthError ?? null,
  });

  mockDeleteWorkspace.mockResolvedValue(undefined);
  mockRemoveGitDataRepo.mockResolvedValue(undefined);
  mockAbortAllUserSessions.mockReturnValue(undefined);

  mockStorageFrom.mockReturnValue({
    list: mockStorageList,
    remove: mockStorageRemove,
  });
  mockStorageList.mockResolvedValue({ data: [], error: null });
  mockStorageRemove.mockResolvedValue({ data: [], error: null });

  // Per plan rev-2 AC25: abort-DSAR-jobs is the first cascade step
  // (UPDATE in-flight jobs to failed). The mock returns success by
  // default — tests that want to track ordering install their own
  // tracker via mockFrom.mockImplementation.
  mockFrom.mockImplementation(() => ({
    update: () => ({
      eq: () => ({
        in: () => Promise.resolve({ error: null }),
      }),
    }),
    delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
    // mig 068 #4318 step 3.901 ordering-guard probe + Phase 5 storage-purge enum.
    select: () => ({
      eq: () => Promise.resolve({ count: 1, data: [], error: null }),
    }),
  }));

  // anonymise_dsar_export_audit_pii RPC default — success.
  mockRpc.mockResolvedValue({ data: 0, error: null });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("deleteAccount", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("returns error when confirmEmail does not match user email", async () => {
    setupSupabaseMocks({ user: { id: "user-123", email: "real@example.com" } });

    const result = await deleteAccount("user-123", "wrong@example.com");

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/email.*match/i);
  });

  test("returns error when user is not found", async () => {
    setupSupabaseMocks({
      user: null,
      getUserError: { message: "User not found" },
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/not found/i);
  });

  test("executes deletion cascade in correct order per plan rev-2 AC25", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockAbortAllUserSessions.mockImplementation(() => {
      callOrder.push("abort");
    });
    mockDeleteWorkspace.mockImplementation(async () => {
      callOrder.push("workspace");
    });
    mockFrom.mockImplementation((table: string) => {
      if (table === "dsar_export_jobs") {
        return {
          update: () => ({
            eq: () => ({
              in: () => {
                callOrder.push("abort-dsar-jobs");
                return Promise.resolve({ error: null });
              },
            }),
          }),
        };
      }
      if (table === "users") {
        return {
          delete: () => ({
            eq: () => {
              callOrder.push("public.users");
              return Promise.resolve({ error: null });
            },
          }),
        };
      }
      return {
        delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
        // mig 068 #4318 step 3.901 ordering-guard probe on workspace_members.
        select: () => ({
          eq: () => Promise.resolve({ count: 1, data: [], error: null }),
        }),
      };
    });
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_dsar_export_audit_pii") {
        callOrder.push("anonymise-dsar-audit");
      } else if (name === "anonymise_tc_acceptances") {
        callOrder.push("anonymise-tc-acceptances");
      } else if (name === "anonymise_workspace_member_attestations") {
        callOrder.push("anonymise-workspace-attestations");
      } else if (name === "anonymise_departed_user_across_workspaces") {
        callOrder.push("anonymise-departed-user-messages");
      } else if (name === "anonymise_workspace_member_removals") {
        callOrder.push("anonymise-workspace-removals");
      } else if (name === "anonymise_workspace_members") {
        callOrder.push("anonymise-workspace-members");
      } else if (name === "anonymise_organization_membership") {
        callOrder.push("anonymise-org-membership");
      } else if (name === "anonymise_workspace_member_actions") {
        callOrder.push("anonymise-workspace-actions");
      } else if (name === "anonymise_byok_delegations") {
        callOrder.push("anonymise-byok-delegations");
      } else if (name === "anonymise_byok_delegation_acceptances") {
        callOrder.push("anonymise-byok-acceptances");
      } else if (name === "anonymise_byok_delegation_withdrawals") {
        callOrder.push("anonymise-byok-withdrawals");
      }
      return { data: 0, error: null };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(callOrder).toEqual([
      "abort-dsar-jobs",
      "abort",
      "workspace",
      "anonymise-dsar-audit",
      "anonymise-tc-acceptances",
      "anonymise-workspace-attestations",
      "anonymise-departed-user-messages",
      "anonymise-workspace-removals",
      "anonymise-workspace-members",
      "anonymise-org-membership",
      "anonymise-workspace-actions",
      "anonymise-byok-delegations",
      "anonymise-byok-acceptances",
      "anonymise-byok-withdrawals",
      "auth",
    ]);
  });

  test("returns success on successful deletion", async () => {
    setupSupabaseMocks();

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(result.error).toBeUndefined();
  });

  test("calls abortSession with the correct userId", async () => {
    setupSupabaseMocks();

    await deleteAccount("user-123", "test@example.com");

    expect(mockAbortAllUserSessions).toHaveBeenCalledWith("user-123");
  });

  test("calls deleteWorkspace with the correct userId", async () => {
    setupSupabaseMocks();

    await deleteAccount("user-123", "test@example.com");

    expect(mockDeleteWorkspace).toHaveBeenCalledWith("user-123");
  });

  test("erases the shared git-data bare repo for the deleted user (Art. 17 / AC9)", async () => {
    setupSupabaseMocks();

    await deleteAccount("user-123", "test@example.com");

    // userId === workspaces.id (mig 053 N2 invariant) → the sole-owned workspace's
    // git-data repo is keyed on userId, mirroring deleteWorkspace(userId). Best-effort
    // (removeGitDataRepo is a no-op at flag-off), so the reach — not the transport — is
    // what this asserts; the flag gate + key authority are covered in
    // git-data-replication.test.ts.
    expect(mockRemoveGitDataRepo).toHaveBeenCalledWith("user-123");
  });

  test("when auth deletion fails, public.users data remains intact (no partial deletion)", async () => {
    setupSupabaseMocks({
      deleteAuthError: { message: "Auth API unavailable" },
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/failed/i);
    // Critical: from("users").delete() must NOT be called when auth fails first
    expect(mockFrom).not.toHaveBeenCalledWith("users");
  });

  test("returns error when auth deletion fails", async () => {
    setupSupabaseMocks({
      deleteAuthError: { message: "Auth deletion failed" },
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/failed/i);
  });

  // -------------------------------------------------------------------------
  // Storage blob purge (step 3.5) — GDPR Article 17
  // -------------------------------------------------------------------------

  test("purges Storage blobs with correct paths from nested folder/file listing", async () => {
    setupSupabaseMocks();

    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
        return { data: [{ name: "conv-1" }, { name: "conv-2" }], error: null };
      }
      if (folder === "user-123/conv-1") {
        return { data: [{ name: "img1.png" }, { name: "doc1.pdf" }], error: null };
      }
      if (folder === "user-123/conv-2") {
        return { data: [{ name: "img2.jpg" }], error: null };
      }
      return { data: [], error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(mockStorageFrom).toHaveBeenCalledWith("chat-attachments");
    expect(mockStorageRemove).toHaveBeenCalledWith([
      "user-123/conv-1/img1.png",
      "user-123/conv-1/doc1.pdf",
      "user-123/conv-2/img2.jpg",
    ]);
  });

  test("Storage list() error is non-fatal — deletion still succeeds", async () => {
    setupSupabaseMocks();

    mockStorageList.mockRejectedValue(new Error("Storage unavailable"));

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(mockAuth.admin.deleteUser).toHaveBeenCalledWith("user-123");
  });

  test("Storage remove() error is non-fatal — deletion still succeeds", async () => {
    setupSupabaseMocks();

    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
        return { data: [{ name: "conv-1" }], error: null };
      }
      if (folder === "user-123/conv-1") {
        return { data: [{ name: "file.png" }], error: null };
      }
      return { data: [], error: null };
    });
    mockStorageRemove.mockRejectedValue(new Error("Storage remove failed"));

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(mockAuth.admin.deleteUser).toHaveBeenCalledWith("user-123");
  });

  test("cascade order: full AC25 sequence with storage purge + anonymise", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockAbortAllUserSessions.mockImplementation(() => {
      callOrder.push("abort");
    });
    mockDeleteWorkspace.mockImplementation(async () => {
      callOrder.push("workspace");
    });
    mockFrom.mockImplementation((table: string) => {
      if (table === "dsar_export_jobs") {
        return {
          update: () => ({
            eq: () => ({
              in: () => {
                callOrder.push("abort-dsar-jobs");
                return Promise.resolve({ error: null });
              },
            }),
          }),
        };
      }
      return {
        delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
        // mig 068 #4318 step 3.901 ordering-guard probe on workspace_members.
        select: () => ({
          eq: () => Promise.resolve({ count: 1, data: [], error: null }),
        }),
      };
    });
    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
        // chat-attachments + dsar-exports both list the same prefix;
        // we yield a single conv folder for chat-attachments and a
        // file for dsar-exports's first list.
        return { data: [{ name: "conv-1" }], error: null };
      }
      if (folder === "user-123/conv-1") {
        return { data: [{ name: "file.png" }], error: null };
      }
      return { data: [], error: null };
    });
    mockStorageRemove.mockImplementation(async () => {
      callOrder.push("storage-purge");
      return { data: [], error: null };
    });
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_dsar_export_audit_pii") {
        callOrder.push("anonymise-dsar-audit");
      } else if (name === "anonymise_tc_acceptances") {
        callOrder.push("anonymise-tc-acceptances");
      } else if (name === "anonymise_workspace_member_attestations") {
        callOrder.push("anonymise-workspace-attestations");
      } else if (name === "anonymise_departed_user_across_workspaces") {
        callOrder.push("anonymise-departed-user-messages");
      } else if (name === "anonymise_workspace_member_removals") {
        callOrder.push("anonymise-workspace-removals");
      } else if (name === "anonymise_workspace_members") {
        callOrder.push("anonymise-workspace-members");
      } else if (name === "anonymise_organization_membership") {
        callOrder.push("anonymise-org-membership");
      } else if (name === "anonymise_workspace_member_actions") {
        callOrder.push("anonymise-workspace-actions");
      } else if (name === "anonymise_byok_delegations") {
        callOrder.push("anonymise-byok-delegations");
      } else if (name === "anonymise_byok_delegation_acceptances") {
        callOrder.push("anonymise-byok-acceptances");
      } else if (name === "anonymise_byok_delegation_withdrawals") {
        callOrder.push("anonymise-byok-withdrawals");
      }
      return { data: 0, error: null };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    // Storage-purge runs twice (chat-attachments then dsar-exports).
    // The trace collapses duplicate adjacent steps for readability.
    const deduped: string[] = [];
    for (const step of callOrder) {
      if (deduped[deduped.length - 1] !== step) deduped.push(step);
    }
    expect(deduped).toEqual([
      "abort-dsar-jobs",
      "abort",
      "workspace",
      "storage-purge",
      "anonymise-dsar-audit",
      "anonymise-tc-acceptances",
      "anonymise-workspace-attestations",
      "anonymise-departed-user-messages",
      "anonymise-workspace-removals",
      "anonymise-workspace-members",
      "anonymise-org-membership",
      "anonymise-workspace-actions",
      "anonymise-byok-delegations",
      "anonymise-byok-acceptances",
      "anonymise-byok-withdrawals",
      "auth",
    ]);
  });

  test("Art. 17 — anonymise_email_triage_items precedes auth.admin.deleteUser (FK ON DELETE RESTRICT, migration 102)", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockRpc.mockImplementation(async (name: string) => {
      callOrder.push(`rpc:${name}`);
      return { data: 0, error: null };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth.deleteUser");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    const triageIdx = callOrder.indexOf("rpc:anonymise_email_triage_items");
    const authIdx = callOrder.indexOf("auth.deleteUser");
    expect(triageIdx).toBeGreaterThanOrEqual(0);
    expect(authIdx).toBeGreaterThanOrEqual(0);
    expect(triageIdx).toBeLessThan(authIdx);
  });

  test("Art. 17 — anonymise_email_triage_items failure aborts cascade BEFORE auth-delete", async () => {
    setupSupabaseMocks();

    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_email_triage_items") {
        return { data: null, error: { message: "RPC unavailable" } };
      }
      return { data: 0, error: null };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(false);
    expect(mockAuth.admin.deleteUser).not.toHaveBeenCalled();
  });

  test("Art. 17 — anonymise_tc_acceptances precedes auth.admin.deleteUser (FK ON DELETE RESTRICT)", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockRpc.mockImplementation(async (name: string) => {
      callOrder.push(`rpc:${name}`);
      return { data: 0, error: null };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth.deleteUser");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    const tcIdx = callOrder.indexOf("rpc:anonymise_tc_acceptances");
    const authIdx = callOrder.indexOf("auth.deleteUser");
    expect(tcIdx).toBeGreaterThanOrEqual(0);
    expect(authIdx).toBeGreaterThanOrEqual(0);
    expect(tcIdx).toBeLessThan(authIdx);
  });

  test("Art. 17 — anonymise_tc_acceptances failure aborts cascade BEFORE auth-delete", async () => {
    setupSupabaseMocks();

    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_tc_acceptances") {
        return { data: null, error: { message: "RPC unavailable" } };
      }
      return { data: 0, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(false);
    expect(result.error).toMatch(/failed/i);
    // FK is ON DELETE RESTRICT — auth-delete must NOT be attempted
    // because the cascade would abort with a FK violation anyway.
    expect(mockAuth.admin.deleteUser).not.toHaveBeenCalled();
  });

  test("paginates when folder list returns PAGE_SIZE (1000) items", async () => {
    setupSupabaseMocks();

    const fullPage = Array.from({ length: 1_000 }, (_, i) => ({ name: `conv-${i}` }));

    // The chat-attachments list is called BEFORE the dsar-exports
    // list. We track the chat-attachments calls only — bucket
    // discrimination is implicit via mockStorageFrom.
    let chatAttachmentsListCount = 0;
    const bucketCalls: string[] = [];
    mockStorageFrom.mockImplementation((bucket: string) => {
      bucketCalls.push(bucket);
      return { list: mockStorageList, remove: mockStorageRemove };
    });

    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
        // Both buckets list the same user prefix; count only the calls
        // that arrive while chat-attachments is the active bucket.
        const activeBucket = bucketCalls[bucketCalls.length - 1];
        if (activeBucket === "chat-attachments") {
          chatAttachmentsListCount++;
          if (chatAttachmentsListCount === 1) {
            return { data: fullPage, error: null };
          }
        }
        return { data: [], error: null };
      }
      return { data: [], error: null };
    });

    await deleteAccount("user-123", "test@example.com");

    // With pagination, chat-attachments folder-level list must be
    // called exactly twice (first page returned PAGE_SIZE items ->
    // fetch second page -> empty -> done).
    expect(chatAttachmentsListCount).toBe(2);
  });

  test("AC25 recovery: anonymise succeeds, auth-delete fails — anonymise re-runs as no-op on retry", async () => {
    // The cascade is designed to be re-runnable. anonymise rows
    // already with requester_ip=NULL + user_agent=NULL is a no-op
    // on the next call (per migration 041 RPC). This test asserts
    // the cascade returns a failure (so callers can retry) WITHOUT
    // skipping anonymise on the second attempt.
    setupSupabaseMocks({
      deleteAuthError: { message: "Auth API timeout" },
    });

    let anonymiseCallCount = 0;
    mockRpc.mockImplementation(async (name: string) => {
      if (name === "anonymise_dsar_export_audit_pii") {
        anonymiseCallCount++;
        return { data: anonymiseCallCount === 1 ? 5 : 0, error: null };
      }
      return { data: 0, error: null };
    });

    // First attempt: anonymise runs, auth-delete fails.
    const first = await deleteAccount("user-123", "test@example.com");
    expect(first.success).toBe(false);
    expect(anonymiseCallCount).toBe(1);

    // Second attempt: anonymise re-runs (no-op against the empty
    // result set), then auth-delete is re-attempted. The RPC MUST
    // be called again — skipping it would risk anonymise being
    // missed on a code path that succeeded mid-cascade.
    mockAuth.admin.deleteUser.mockResolvedValueOnce({ data: {}, error: null });
    const second = await deleteAccount("user-123", "test@example.com");
    expect(second.success).toBe(true);
    expect(anonymiseCallCount).toBe(2);
  });

  test("does not call remove() when user has zero attachments", async () => {
    setupSupabaseMocks();
    // Default mock already returns { data: [], error: null }

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(mockStorageRemove).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// Rate limiting for account deletion (reuses SlidingWindowCounter)
// ---------------------------------------------------------------------------

describe("account deletion rate limiting", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("allows 1 deletion request per 60s window", () => {
    const limiter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 1,
    });

    expect(limiter.isAllowed("user-123")).toBe(true);
    expect(limiter.isAllowed("user-123")).toBe(false);
  });

  test("allows deletion again after window expires", () => {
    const limiter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 1,
    });

    expect(limiter.isAllowed("user-123")).toBe(true);
    expect(limiter.isAllowed("user-123")).toBe(false);

    vi.advanceTimersByTime(61_000);

    expect(limiter.isAllowed("user-123")).toBe(true);
  });

  test("tracks users independently for deletion rate limit", () => {
    const limiter = new SlidingWindowCounter({
      windowMs: 60_000,
      maxRequests: 1,
    });

    expect(limiter.isAllowed("user-a")).toBe(true);
    expect(limiter.isAllowed("user-a")).toBe(false);
    // Different user is unaffected
    expect(limiter.isAllowed("user-b")).toBe(true);
  });
});
