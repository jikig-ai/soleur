import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockTryCreateVision,
  mockValidateOrigin,
  mockResolveActiveWorkspacePath,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockTryCreateVision: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockResolveActiveWorkspacePath: vi.fn(),
}));

const serviceClientSentinel = { from: vi.fn() };

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => serviceClientSentinel),
}));

vi.mock("@/server/vision-helpers", () => ({
  tryCreateVision: mockTryCreateVision,
}));

// #5005 — the route now resolves the ACTIVE workspace path via the
// membership-scoped resolver instead of the caller's own `users.workspace_path`
// column. Per-resolver unit coverage lives in
// test/server/kb-active-workspace-scoping.test.ts.
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspacePath: mockResolveActiveWorkspacePath,
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockResolveActiveWorkspacePath.mockResolvedValue("/workspaces/user-1");
});

describe("POST /api/vision", () => {
  test("creates vision with valid content and returns 200", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
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

  test("writes vision.md under the resolver's ACTIVE path for a stale-own-row caller (#5005)", async () => {
    // Post-ADR-044 / invited-member caller: the caller's own
    // `users.workspace_path` is empty, but the resolver resolves a DIVERGENT
    // active workspace path. First-run vision creation must succeed there — NOT
    // 503 "Workspace not provisioned" (the pre-#5005 bug for recent signups).
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
    mockResolveActiveWorkspacePath.mockResolvedValue("/workspaces/active-ws-divergent");
    mockTryCreateVision.mockResolvedValue(undefined);

    const res = await POST(buildRequest({ content: "A valid startup idea here" }));
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    // Resolver invoked with the caller id + the service client — never the
    // caller's own (empty) users row.
    expect(mockResolveActiveWorkspacePath).toHaveBeenCalledWith(
      "user-1",
      serviceClientSentinel,
    );
    expect(mockTryCreateVision).toHaveBeenCalledWith(
      "/workspaces/active-ws-divergent",
      "A valid startup idea here",
    );
  });

  test("returns 401 when user is not authenticated", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: null },
      error: null,
    });

    const res = await POST(buildRequest({ content: "test idea" }));

    expect(res.status).toBe(401);
    expect(mockResolveActiveWorkspacePath).not.toHaveBeenCalled();
  });

  test("returns 400 when content field is missing", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });

    const res = await POST(buildRequest({}));

    expect(res.status).toBe(400);
    expect(mockTryCreateVision).not.toHaveBeenCalled();
  });

  test("returns 500 when vision creation throws", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
    mockTryCreateVision.mockRejectedValueOnce(new Error("EPERM"));

    const res = await POST(buildRequest({ content: "A valid startup idea here" }));

    expect(res.status).toBe(500);
  });

  test("returns 403 when CSRF validation fails", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.com" });

    const res = await POST(buildRequest({ content: "test" }));

    expect(res.status).toBe(403);
  });
});
