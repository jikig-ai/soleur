import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom, mockDeleteWorkspace, mockIsAllowed } =
  vi.hoisted(() => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockDeleteWorkspace: vi.fn(),
    mockIsAllowed: vi.fn(),
  }));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/server/workspace", () => ({
  deleteWorkspace: mockDeleteWorkspace,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.com" })),
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "CSRF rejected" }), { status: 403 }),
  ),
}));

vi.mock("@/server/rate-limiter", () => ({
  SlidingWindowCounter: vi.fn().mockImplementation(() => ({
    isAllowed: mockIsAllowed,
  })),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { DELETE } from "@/app/api/repo/disconnect/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(): Request {
  return new Request("https://app.soleur.com/api/repo/disconnect", {
    method: "DELETE",
    headers: { origin: "https://app.soleur.com" },
  });
}

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

/** Sets up Supabase mock chain for the users table. */
function setupUserMocks(opts: {
  repoStatus?: string;
  selectError?: { message: string } | null;
  updateError?: { message: string } | null;
}) {
  const { repoStatus = "ready", selectError = null, updateError = null } = opts;

  const mockSelectSingle = vi.fn().mockResolvedValue({
    data: selectError ? null : { repo_status: repoStatus },
    error: selectError,
  });
  const mockSelectEq = vi.fn(() => ({ single: mockSelectSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockSelectEq }));

  const mockUpdateEq = vi.fn().mockResolvedValue({ error: updateError });
  const mockUpdate = vi.fn(() => ({ eq: mockUpdateEq }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return { select: mockSelect, update: mockUpdate };
    }
    return {};
  });

  return { mockUpdate };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("DELETE /api/repo/disconnect", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockIsAllowed.mockReturnValue(true);
  });

  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);
  });

  test("returns 429 when rate limited", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    mockIsAllowed.mockReturnValue(false);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(429);

    const body = await res.json();
    expect(body.error).toMatch(/too many/i);
  });

  test("returns 403 on CSRF rejection", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(403);
  });

  test("returns 409 when repo is currently cloning", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "cloning" });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.error).toMatch(/in progress/i);
  });

  test("returns 500 when select query fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupUserMocks({ selectError: { message: "database unreachable" } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);
  });

  test("returns 200 and clears all repo fields on successful disconnect", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    const { mockUpdate } = setupUserMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);

    expect(mockUpdate).toHaveBeenCalledWith({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
      health_snapshot: null,
      workspace_path: "",
      workspace_status: "provisioning",
    });

    expect(mockDeleteWorkspace).toHaveBeenCalledWith(TEST_USER_ID);
  });

  test("workspace cleanup failure still returns 200 (best-effort)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "ready" });
    mockDeleteWorkspace.mockRejectedValue(new Error("Directory already removed"));

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  test("returns 500 when database update fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
    setupUserMocks({ repoStatus: "ready", updateError: { message: "constraint violation" } });

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toMatch(/failed to disconnect/i);
  });

  test("returns 200 idempotently when user has no connected repo", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: TEST_USER_ID } },
    });
    setupUserMocks({ repoStatus: "not_connected" });
    mockDeleteWorkspace.mockResolvedValue(undefined);

    const res = await DELETE(makeRequest());
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.ok).toBe(true);
  });
});
