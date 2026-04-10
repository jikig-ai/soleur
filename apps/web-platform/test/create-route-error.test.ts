import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Hoisted mock functions (vi.mock is hoisted above const declarations)
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockServiceFrom,
  mockCreateRepo,
  mockCaptureException,
  MockGitHubClientError,
} = vi.hoisted(() => {
  class _GitHubClientError extends Error {
    constructor(
      message: string,
      public readonly statusCode: number,
    ) {
      super(message);
    }
  }
  return {
    mockGetUser: vi.fn(),
    mockServiceFrom: vi.fn(),
    mockCreateRepo: vi.fn(),
    mockCaptureException: vi.fn(),
    MockGitHubClientError: _GitHubClientError,
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
  GitHubClientError: MockGitHubClientError,
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

  test("returns specific error message for GitHub client errors (4xx)", async () => {
    mockCreateRepo.mockRejectedValue(
      new MockGitHubClientError("name already exists on this account", 422),
    );

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(422);

    const body = await res.json();
    expect(body.error).toBe("name already exists on this account");
  });

  test("returns static message for internal errors (not GitHubClientError)", async () => {
    mockCreateRepo.mockRejectedValue(
      new Error("GitHub API internal failure"),
    );

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.error).toBe("Failed to create repository");
  });

  test("calls Sentry.captureException on error", async () => {
    const err = new Error("GitHub API rate limit exceeded");
    mockCreateRepo.mockRejectedValue(err);

    await POST(makeRequest({ name: "my-repo", private: true }));

    expect(mockCaptureException).toHaveBeenCalledWith(err);
  });

  test("returns generic message for non-Error throws", async () => {
    mockCreateRepo.mockRejectedValue("something broke");

    const res = await POST(makeRequest({ name: "my-repo", private: true }));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.error).toBe("Failed to create repository");
  });
});
