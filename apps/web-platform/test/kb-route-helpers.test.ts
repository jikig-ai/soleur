import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockGitWithAuth,
  mockIsPathInWorkspace,
  mockLstat,
  mockValidateOrigin,
  mockRejectCsrf,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockGitWithAuth: vi.fn(),
  mockIsPathInWorkspace: vi.fn(),
  mockLstat: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockRejectCsrf: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/server/git-auth", () => ({
  gitWithInstallationAuth: mockGitWithAuth,
}));

vi.mock("@/server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));

vi.mock("node:fs", () => ({
  promises: { lstat: mockLstat },
}));

// ---------------------------------------------------------------------------
// Import helpers AFTER mocks
// ---------------------------------------------------------------------------

import {
  authenticateAndResolveKbPath,
  syncWorkspace,
} from "@/server/kb-route-helpers";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_INSTALLATION_ID = 12345;
const TEST_WORKSPACE_PATH = "/workspaces/test-user";
const TEST_REPO_URL = "https://github.com/test-owner/test-repo";

function createRequest(): Request {
  return new Request("http://localhost:3000/api/kb/file/overview/test.pdf", {
    method: "DELETE",
    headers: { Origin: "https://app.soleur.ai" },
  });
}

function createParams(pathSegments: string[]): Promise<{ path: string[] }> {
  return Promise.resolve({ path: pathSegments });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({ data: { user: { id: TEST_USER_ID } } });
}

function setupUserData(overrides: Record<string, unknown> = {}) {
  const mockSingle = vi.fn().mockResolvedValue({
    data: {
      workspace_path: TEST_WORKSPACE_PATH,
      workspace_status: "ready",
      repo_url: TEST_REPO_URL,
      github_installation_id: TEST_INSTALLATION_ID,
      ...overrides,
    },
    error: null,
  });
  const mockEq = vi.fn(() => ({ single: mockSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));
  mockFrom.mockImplementation((table: string) => {
    if (table === "users") return { select: mockSelect };
    return {};
  });
}

function setupHappyPath() {
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  setupAuthenticatedUser();
  setupUserData();
  mockIsPathInWorkspace.mockReturnValue(true);
  mockLstat.mockResolvedValue({
    isSymbolicLink: () => false,
    isFile: () => true,
    isDirectory: () => false,
  });
}

const fakeLogger = {
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  // pino Logger signature has many methods; tests only require these.
} as unknown as import("pino").Logger;

// ---------------------------------------------------------------------------
// Tests — authenticateAndResolveKbPath
// ---------------------------------------------------------------------------

describe("authenticateAndResolveKbPath", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("returns CSRF response when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.com" });
    const csrfResponse = new Response(JSON.stringify({ error: "Forbidden" }), {
      status: 403,
    });
    mockRejectCsrf.mockReturnValue(csrfResponse);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response).toBe(csrfResponse);
      expect(mockRejectCsrf).toHaveBeenCalledWith("api/kb/file", "https://evil.com");
    }
  });

  test("returns 401 when unauthenticated", async () => {
    mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(401);
    }
  });

  test("returns 503 when workspace is not ready", async () => {
    setupHappyPath();
    setupUserData({ workspace_status: "provisioning" });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(503);
  });

  test("returns 400 when no repo connected", async () => {
    setupHappyPath();
    setupUserData({ repo_url: null });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(400);
  });

  test("returns 400 for empty path", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(createRequest(), createParams([]));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/file path required/i);
    }
  });

  test("returns 400 for null byte in path", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test\0evil.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/null byte/i);
    }
  });

  test("returns 400 for .md extension when blockMarkdown: true", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "readme.md"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/markdown/i);
    }
  });

  test("returns 400 for path traversal outside workspace", async () => {
    setupHappyPath();
    mockIsPathInWorkspace.mockReturnValue(false);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["..", "..", "etc", "passwd.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.response.status).toBe(400);
      const body = await result.response.json();
      expect(body.error).toMatch(/invalid path/i);
    }
  });

  test("returns 403 when target is a symlink", async () => {
    setupHappyPath();
    mockLstat.mockResolvedValue({
      isSymbolicLink: () => true,
      isFile: () => false,
      isDirectory: () => false,
    });

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "link.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(403);
  });

  test("proceeds OK when lstat returns ENOENT (file not on disk)", async () => {
    setupHappyPath();
    const enoent = new Error("ENOENT") as NodeJS.ErrnoException;
    enoent.code = "ENOENT";
    mockLstat.mockRejectedValue(enoent);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "remote-only.pdf"]),
    );
    expect(result.ok).toBe(true);
  });

  test("returns 403 when lstat fails with non-ENOENT error", async () => {
    setupHappyPath();
    const permErr = new Error("EACCES") as NodeJS.ErrnoException;
    permErr.code = "EACCES";
    mockLstat.mockRejectedValue(permErr);

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "locked.pdf"]),
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.response.status).toBe(403);
  });

  test("happy path returns populated context", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "test.pdf"]),
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.ctx).toMatchObject({
        user: { id: TEST_USER_ID },
        userData: {
          workspace_path: TEST_WORKSPACE_PATH,
          repo_url: TEST_REPO_URL,
          github_installation_id: TEST_INSTALLATION_ID,
        },
        owner: "test-owner",
        repo: "test-repo",
        relativePath: "overview/test.pdf",
        filePath: "knowledge-base/overview/test.pdf",
        ext: ".pdf",
      });
      expect(result.ctx.kbRoot).toContain("knowledge-base");
      expect(result.ctx.fullPath).toContain("overview/test.pdf");
    }
  });

  test("blockMarkdown: false allows .md paths through", async () => {
    setupHappyPath();

    const result = await authenticateAndResolveKbPath(
      createRequest(),
      createParams(["overview", "readme.md"]),
      { endpoint: "api/kb/file", blockMarkdown: false },
    );
    expect(result.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Tests — syncWorkspace
// ---------------------------------------------------------------------------

describe("syncWorkspace", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGitWithAuth.mockResolvedValue(Buffer.from(""));
  });

  test("returns ok:true when git pull succeeds; delegates auth to gitWithInstallationAuth", async () => {
    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "delete" },
    );
    expect(result.ok).toBe(true);

    expect(mockGitWithAuth).toHaveBeenCalledTimes(1);
    const [args, installationId, opts] = mockGitWithAuth.mock.calls[0];
    expect(args).toEqual(["pull", "--ff-only"]);
    expect(installationId).toBe(TEST_INSTALLATION_ID);
    expect(opts).toMatchObject({
      cwd: TEST_WORKSPACE_PATH,
      timeout: 30_000,
    });
  });

  test("returns ok:false when git pull fails", async () => {
    const pullErr = new Error("merge conflict");
    mockGitWithAuth.mockRejectedValue(pullErr);

    const result = await syncWorkspace(
      TEST_INSTALLATION_ID,
      TEST_WORKSPACE_PATH,
      fakeLogger,
      { userId: TEST_USER_ID, op: "rename" },
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe(pullErr);
  });

  test("logger.error is called with op tag on failure", async () => {
    mockGitWithAuth.mockRejectedValue(new Error("boom"));
    const errSpy = vi.fn();
    const logger = {
      info: vi.fn(),
      warn: vi.fn(),
      error: errSpy,
    } as unknown as import("pino").Logger;

    await syncWorkspace(TEST_INSTALLATION_ID, TEST_WORKSPACE_PATH, logger, {
      userId: TEST_USER_ID,
      op: "upload",
    });

    expect(errSpy).toHaveBeenCalledWith(
      expect.objectContaining({ userId: TEST_USER_ID, op: "upload" }),
      expect.stringContaining("upload"),
    );
  });
});
