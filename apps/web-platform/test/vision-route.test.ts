import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockTryCreateVision, mockValidateOrigin } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockTryCreateVision: vi.fn(),
    mockValidateOrigin: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/server/vision-helpers", () => ({
  tryCreateVision: mockTryCreateVision,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/vision/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildRequest(body: unknown): Request {
  return new Request("https://app.soleur.ai/api/vision", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
}

function mockQueryBuilder(data: unknown) {
  return {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnValue({
      then: (fn: (v: unknown) => unknown) =>
        Promise.resolve({ data, error: null }).then(fn),
    }),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
});

describe("POST /api/vision", () => {
  test("creates vision with valid content and returns 200", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
    mockFrom.mockReturnValue(
      mockQueryBuilder({ workspace_path: "/workspaces/user-1" }),
    );
    mockTryCreateVision.mockResolvedValue(undefined);

    const res = await POST(buildRequest({ content: "A marketplace for freelance designers" }));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(mockTryCreateVision).toHaveBeenCalledWith(
      "/workspaces/user-1",
      "A marketplace for freelance designers",
    );
  });

  test("returns 401 when user is not authenticated", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: null },
      error: null,
    });

    const res = await POST(buildRequest({ content: "test idea" }));

    expect(res.status).toBe(401);
  });

  test("returns 400 when content field is missing", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });

    const res = await POST(buildRequest({}));

    expect(res.status).toBe(400);
  });

  test("returns 503 when workspace is not provisioned", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
    mockFrom.mockReturnValue(mockQueryBuilder(null));

    const res = await POST(buildRequest({ content: "A valid startup idea" }));

    expect(res.status).toBe(503);
  });

  test("returns 403 when CSRF validation fails", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.com" });

    const res = await POST(buildRequest({ content: "test" }));

    expect(res.status).toBe(403);
  });
});
