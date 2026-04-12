import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { SlidingWindowCounter } from "../server/rate-limiter";

// ---------------------------------------------------------------------------
// Mock Supabase service client — must be defined before importing the module
// ---------------------------------------------------------------------------

const mockFrom = vi.fn();
const mockAuth = {
  admin: {
    getUserById: vi.fn(),
    deleteUser: vi.fn(),
  },
};
const mockStorageList = vi.fn();
const mockStorageRemove = vi.fn();
const mockStorageFrom = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: mockFrom,
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
  mockAbortAllUserSessions.mockReturnValue(undefined);

  mockStorageFrom.mockReturnValue({
    list: mockStorageList,
    remove: mockStorageRemove,
  });
  mockStorageList.mockResolvedValue({ data: [], error: null });
  mockStorageRemove.mockResolvedValue({ data: [], error: null });
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

  test("executes deletion cascade in correct order: abort → workspace → auth (FK cascade)", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockAbortAllUserSessions.mockImplementation(() => {
      callOrder.push("abort");
    });
    mockDeleteWorkspace.mockImplementation(async () => {
      callOrder.push("workspace");
    });
    mockFrom.mockImplementation((table: string) => {
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
      return { delete: () => ({ eq: () => Promise.resolve({ error: null }) }) };
    });
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    // Auth deletion triggers FK cascade — no explicit public.users delete step
    expect(callOrder).toEqual(["abort", "workspace", "auth"]);
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

  test("cascade order: Storage purge runs between workspace deletion and auth deletion", async () => {
    setupSupabaseMocks();
    const callOrder: string[] = [];

    mockAbortAllUserSessions.mockImplementation(() => {
      callOrder.push("abort");
    });
    mockDeleteWorkspace.mockImplementation(async () => {
      callOrder.push("workspace");
    });
    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
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
    mockAuth.admin.deleteUser.mockImplementation(async () => {
      callOrder.push("auth");
      return { data: {}, error: null };
    });

    const result = await deleteAccount("user-123", "test@example.com");

    expect(result.success).toBe(true);
    expect(callOrder).toEqual(["abort", "workspace", "storage-purge", "auth"]);
  });

  test("paginates when folder list returns PAGE_SIZE (1000) items", async () => {
    setupSupabaseMocks();

    const fullPage = Array.from({ length: 1_000 }, (_, i) => ({ name: `conv-${i}` }));

    let folderListCallCount = 0;
    mockStorageList.mockImplementation(async (folder: string) => {
      if (folder === "user-123") {
        folderListCallCount++;
        if (folderListCallCount === 1) return { data: fullPage, error: null };
        return { data: [], error: null };
      }
      // Per-conversation files — return empty for pagination test
      return { data: [], error: null };
    });

    await deleteAccount("user-123", "test@example.com");

    // With pagination, folder-level list must be called at least twice
    // (first page returned exactly PAGE_SIZE items → must fetch second page)
    expect(folderListCallCount).toBeGreaterThanOrEqual(2);
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
