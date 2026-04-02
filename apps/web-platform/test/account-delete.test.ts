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

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    auth: mockAuth,
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
