import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockGithubApiGet,
  mockGithubApiDelete,
  mockGenerateInstallationToken,
  mockRandomCredentialPath,
  mockIsPathInWorkspace,
  mockExecFile,
  mockWriteFileSync,
  mockUnlinkSync,
  mockLstat,
  MockGitHubApiError,
} = vi.hoisted(() => {
  class MockGitHubApiError extends Error {
    statusCode: number;
    constructor(message: string, statusCode: number) {
      super(message);
      this.name = "GitHubApiError";
      this.statusCode = statusCode;
    }
  }
  return {
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockGithubApiGet: vi.fn(),
    mockGithubApiDelete: vi.fn(),
    mockGenerateInstallationToken: vi.fn(),
    mockRandomCredentialPath: vi.fn(),
    mockIsPathInWorkspace: vi.fn(),
    mockExecFile: vi.fn(),
    mockWriteFileSync: vi.fn(),
    mockUnlinkSync: vi.fn(),
    mockLstat: vi.fn(),
    MockGitHubApiError,
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/github-api", () => ({
  githubApiGet: mockGithubApiGet,
  githubApiDelete: mockGithubApiDelete,
  GitHubApiError: MockGitHubApiError,
}));

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: mockGenerateInstallationToken,
  randomCredentialPath: mockRandomCredentialPath,
  GitHubApiError: MockGitHubApiError,
}));

vi.mock("@/server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

vi.mock("node:child_process", () => ({
  execFile: mockExecFile,
}));

vi.mock("node:util", () => ({
  promisify: vi.fn((fn: unknown) => fn),
}));

vi.mock("node:fs", () => ({
  writeFileSync: mockWriteFileSync,
  unlinkSync: mockUnlinkSync,
  promises: { lstat: mockLstat },
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { DELETE } from "@/app/api/kb/file/[...path]/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_INSTALLATION_ID = 12345;
const TEST_WORKSPACE_PATH = "/workspaces/test-user";
const TEST_REPO_URL = "https://github.com/test-owner/test-repo";

function createRequest(pathSegments: string[], origin?: string): Request {
  const headers = new Headers();
  if (origin) headers.set("Origin", origin);
  const url = `http://localhost:3000/api/kb/file/${pathSegments.join("/")}`;
  return new Request(url, { method: "DELETE", headers });
}

function createParams(pathSegments: string[]): Promise<{ path: string[] }> {
  return Promise.resolve({ path: pathSegments });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: TEST_USER_ID } },
  });
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
    if (table === "users") {
      return { select: mockSelect };
    }
    return {};
  });
}

function setupFullMocks() {
  setupAuthenticatedUser();
  setupUserData();
  mockIsPathInWorkspace.mockReturnValue(true);
  mockGenerateInstallationToken.mockResolvedValue("test-token");
  mockRandomCredentialPath.mockReturnValue("/tmp/git-cred-test-uuid");
  // File is not a symlink
  mockLstat.mockResolvedValue({
    isSymbolicLink: () => false,
    isFile: () => true,
    isDirectory: () => false,
  });
  // File exists on GitHub with a SHA
  mockGithubApiGet.mockResolvedValue({
    sha: "filesha123",
    name: "test.png",
    path: "knowledge-base/overview/test.png",
    type: "file",
  });
  // Successful DELETE
  mockGithubApiDelete.mockResolvedValue({
    commit: { sha: "commitsha456" },
  });
  // Successful git pull
  mockExecFile.mockResolvedValue({ stdout: "", stderr: "" });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("DELETE /api/kb/file/[...path]", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // 1. CSRF validation
  test("returns 403 when CSRF validation fails", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const req = createRequest(["overview", "test.png"], "https://evil.com");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(403);
  });

  // 2. Auth
  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);
  });

  // 3. Workspace not ready
  test("returns 503 when workspace is not ready", async () => {
    setupAuthenticatedUser();
    setupUserData({ workspace_status: "provisioning" });

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(503);
  });

  // 4. Null byte in path
  test("returns 400 for null byte in path", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test\0evil.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test\0evil.png"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/null byte/i);
  });

  // 5. Path traversal
  test("returns 400 for path traversal", async () => {
    setupFullMocks();
    mockIsPathInWorkspace.mockReturnValue(false);

    const req = createRequest(["..", "..", "etc", "passwd"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["..", "..", "etc", "passwd"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/invalid path/i);
  });

  // 6. Symlink target
  test("returns 403 for symlink target", async () => {
    setupFullMocks();
    mockLstat.mockResolvedValue({
      isSymbolicLink: () => true,
      isFile: () => false,
      isDirectory: () => false,
    });

    const req = createRequest(["overview", "link.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "link.png"]) });
    expect(res.status).toBe(403);
  });

  // 7. Non-existent file (GitHub returns 404)
  test("returns 404 when file does not exist on GitHub", async () => {
    setupFullMocks();
    mockGithubApiGet.mockRejectedValue(
      new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/missing.png", 404),
    );

    const req = createRequest(["overview", "missing.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "missing.png"]) });
    expect(res.status).toBe(404);
  });

  // 8. .md file rejection
  test("returns 400 for .md file deletion attempt", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "readme.md"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "readme.md"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/markdown/i);
  });

  // 9. Happy path — successful deletion
  test("returns 200 with commitSha on successful deletion", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.commitSha).toBe("commitsha456");

    // Verify GitHub API calls
    expect(mockGithubApiGet).toHaveBeenCalledWith(
      TEST_INSTALLATION_ID,
      "/repos/test-owner/test-repo/contents/knowledge-base/overview/test.png",
    );
    expect(mockGithubApiDelete).toHaveBeenCalledWith(
      TEST_INSTALLATION_ID,
      "/repos/test-owner/test-repo/contents/knowledge-base/overview/test.png",
      expect.objectContaining({ sha: "filesha123" }),
    );
  });

  // 10. Workspace sync failure
  test("returns 500 with SYNC_FAILED when git pull fails", async () => {
    setupFullMocks();
    mockExecFile.mockRejectedValue(new Error("git pull failed: merge conflict"));

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.code).toBe("SYNC_FAILED");
  });

  // 11. SHA mismatch (concurrent modification)
  test("returns 409 when GitHub returns SHA mismatch", async () => {
    setupFullMocks();
    mockGithubApiDelete.mockRejectedValue(
      new MockGitHubApiError("GitHub API request failed: 409 /repos/test-owner/test-repo/contents/knowledge-base/overview/test.png", 409),
    );

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.error).toMatch(/modified/i);
  });

  // 12. Directory path (not a file)
  test("returns 400 when path points to a directory on GitHub", async () => {
    setupFullMocks();
    // GitHub returns an array for directories
    mockGithubApiGet.mockResolvedValue([
      { name: "file1.png", type: "file" },
      { name: "file2.png", type: "file" },
    ]);

    const req = createRequest(["overview"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/directory/i);
  });

  // 13. File exists on GitHub but not locally — skip symlink check
  test("skips symlink check when file does not exist locally", async () => {
    setupFullMocks();
    // lstat throws ENOENT (file not on disk)
    const enoent = new Error("ENOENT: no such file or directory") as NodeJS.ErrnoException;
    enoent.code = "ENOENT";
    mockLstat.mockRejectedValue(enoent);

    const req = createRequest(["overview", "remote-only.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "remote-only.png"]) });
    expect(res.status).toBe(200);

    // GitHub API should still have been called
    expect(mockGithubApiDelete).toHaveBeenCalled();
  });

  // 14. Credential helper cleanup after success
  test("credential helper is cleaned up after successful deletion", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(200);

    expect(mockWriteFileSync).toHaveBeenCalledWith(
      "/tmp/git-cred-test-uuid",
      expect.stringContaining("x-access-token"),
      expect.objectContaining({ mode: 0o700 }),
    );
    expect(mockUnlinkSync).toHaveBeenCalledWith("/tmp/git-cred-test-uuid");
  });

  // 15. Credential helper cleanup after sync failure
  test("credential helper is cleaned up after sync failure", async () => {
    setupFullMocks();
    mockExecFile.mockRejectedValue(new Error("git pull failed"));

    const req = createRequest(["overview", "test.png"], "https://app.soleur.ai");
    const res = await DELETE(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(500);

    expect(mockUnlinkSync).toHaveBeenCalledWith("/tmp/git-cred-test-uuid");
  });
});
