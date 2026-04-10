import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Hoisted mock functions (vi.mock is hoisted above const declarations)
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockServiceFrom,
  mockCreateRepo,
  mockCaptureException,
  GitHubApiError,
} = vi.hoisted(() => {
  class GitHubApiError extends Error {
    constructor(
      message: string,
      public readonly statusCode: number,
    ) {
      super(message);
      this.name = "GitHubApiError";
    }
  }
  return {
    mockGetUser: vi.fn(),
    mockServiceFrom: vi.fn(),
    mockCreateRepo: vi.fn(),
    mockCaptureException: vi.fn(),
    GitHubApiError,
  };
});

// ---------------------------------------------------------------------------
// Mock modules BEFORE importing the route handler
// ---------------------------------------------------------------------------

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
  createServiceClient: () => ({
    from: mockServiceFrom,
  }),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

vi.mock("@/server/github-app", () => ({
  createRepo: mockCreateRepo,
  GitHubApiError,
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
}));

import { POST } from "../app/api/repo/create/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(body: Record<string, unknown>) {
  return new Request("https://app.soleur.ai/api/repo/create", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/repo/create — error handling", () => {
  beforeEach(() => {
    vi.clearAllMocks();

    // Standard happy-path mocks
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-123" } },
    });

    mockServiceFrom.mockReturnValue({
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: { github_installation_id: 999 },
            error: null,
          }),
        }),
      }),
    });
  });

  test("returns 409 with specific message for GitHub 422 (duplicate name)", async () => {
    mockCreateRepo.mockRejectedValue(
      new GitHubApiError("name already exists on this account", 422),
    );

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.error).toBe("name already exists on this account");
    expect(mockCaptureException).not.toHaveBeenCalled();
  });

  test("returns 403 for GitHub 403 (permission denied)", async () => {
    mockCreateRepo.mockRejectedValue(
      new GitHubApiError("Resource not accessible by integration", 403),
    );

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(403);

    const body = await res.json();
    expect(body.error).toBe("Resource not accessible by integration");
    expect(mockCaptureException).not.toHaveBeenCalled();
  });

  test("returns 500 and calls Sentry for GitHubApiError with 500 status", async () => {
    const err = new GitHubApiError("GitHub server error", 500);
    mockCreateRepo.mockRejectedValue(err);

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.error).toBe("Failed to create repository");
    expect(mockCaptureException).toHaveBeenCalledWith(err);
  });

  test("returns 500 and calls Sentry for generic errors", async () => {
    const err = new Error("GitHub API rate limit exceeded");
    mockCreateRepo.mockRejectedValue(err);

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(500);

    expect(mockCaptureException).toHaveBeenCalledWith(err);
  });

  test("returns generic message for non-Error throws", async () => {
    mockCreateRepo.mockRejectedValue("something broke");

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.error).toBe("Failed to create repository");
    expect(mockCaptureException).toHaveBeenCalled();
  });
});
