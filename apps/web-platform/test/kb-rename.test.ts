import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockGithubApiGet,
  mockGithubApiPost,
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
    mockGithubApiPost: vi.fn(),
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
  githubApiPost: mockGithubApiPost,
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

import { PATCH } from "@/app/api/kb/file/[...path]/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_INSTALLATION_ID = 12345;
const TEST_WORKSPACE_PATH = "/workspaces/test-user";
const TEST_REPO_URL = "https://github.com/test-owner/test-repo";

function createRequest(pathSegments: string[], body: Record<string, unknown>): Request {
  const url = `http://localhost:3000/api/kb/file/${pathSegments.join("/")}`;
  return new Request(url, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Origin: "https://app.soleur.ai",
    },
    body: JSON.stringify(body),
  });
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
  // File exists on GitHub with a blob SHA
  mockGithubApiGet.mockImplementation((_id: number, path: string) => {
    // Repo metadata API — returns default branch
    if (path.match(/\/repos\/[^/]+\/[^/]+$/) && !path.includes("/contents/")) {
      return Promise.resolve({
        default_branch: "main",
      });
    }
    // Contents API — returns file metadata
    if (path.includes("/contents/")) {
      return Promise.resolve({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      });
    }
    // Git Refs API — returns current ref
    if (path.includes("/git/ref/")) {
      return Promise.resolve({
        object: { sha: "commitsha000", type: "commit" },
      });
    }
    // Git Commits API — returns commit with tree SHA
    if (path.includes("/git/commits/")) {
      return Promise.resolve({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });
    }
    return Promise.reject(new Error(`Unexpected GET: ${path}`));
  });
  // POST /git/trees — returns new tree
  // POST /git/commits — returns new commit
  // PATCH /git/refs — returns updated ref
  mockGithubApiPost.mockImplementation((_id: number, path: string) => {
    if (path.includes("/git/trees")) {
      return Promise.resolve({ sha: "newtreesha111" });
    }
    if (path.includes("/git/commits")) {
      return Promise.resolve({ sha: "newcommitsha222" });
    }
    if (path.includes("/git/refs/")) {
      return Promise.resolve({
        object: { sha: "newcommitsha222" },
      });
    }
    return Promise.reject(new Error(`Unexpected POST: ${path}`));
  });
  // Successful git pull
  mockExecFile.mockResolvedValue({ stdout: "", stderr: "" });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("PATCH /api/kb/file/[...path] (rename)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // 1. CSRF validation
  test("returns 403 when CSRF validation fails", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(403);
  });

  // 2. Auth
  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);
  });

  // 3. Workspace not ready
  test("returns 503 when workspace is not ready", async () => {
    setupAuthenticatedUser();
    setupUserData({ workspace_status: "provisioning" });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(503);
  });

  // 4. Null byte in path
  test("returns 400 for null byte in path", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test\0evil.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test\0evil.png"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/null byte/i);
  });

  // 5. .md file rejection
  test("returns 400 for .md file rename attempt", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "readme.md"], { newName: "notes.md" });
    const res = await PATCH(req, { params: createParams(["overview", "readme.md"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/markdown/i);
  });

  // 6. Path traversal
  test("returns 400 for path traversal", async () => {
    setupFullMocks();
    mockIsPathInWorkspace.mockReturnValue(false);

    const req = createRequest(["..", "..", "etc", "passwd"], { newName: "evil.png" });
    const res = await PATCH(req, { params: createParams(["..", "..", "etc", "passwd"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/invalid path/i);
  });

  // 7. Symlink target
  test("returns 403 for symlink target", async () => {
    setupFullMocks();
    mockLstat.mockResolvedValue({
      isSymbolicLink: () => true,
      isFile: () => false,
      isDirectory: () => false,
    });

    const req = createRequest(["overview", "link.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "link.png"]) });
    expect(res.status).toBe(403);
  });

  // 8. Empty newName
  test("returns 400 for empty newName", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: "" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 9. Missing newName
  test("returns 400 when newName is missing", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], {});
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 10. Extension change
  test("returns 400 when extension changes (png to jpg)", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: "test.jpg" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/extension/i);
  });

  // 11. Extension change to .md
  test("returns 400 when renaming to .md extension", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: "exploit.md" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 12. Same name
  test("returns 400 when newName is same as current name", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: "test.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/same/i);
  });

  // 13. File not found on GitHub
  test("returns 404 when file not found on GitHub", async () => {
    setupFullMocks();
    mockGithubApiGet.mockRejectedValue(
      new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/missing.png", 404),
    );

    const req = createRequest(["overview", "missing.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "missing.png"]) });
    expect(res.status).toBe(404);
  });

  // 14. Destination already exists
  test("returns 409 when destination file already exists", async () => {
    setupFullMocks();
    // First call: GET old file (exists) — second call: GET new file (also exists)
    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      })
      .mockResolvedValueOnce({
        sha: "existingsha456",
        name: "renamed.png",
        path: "knowledge-base/overview/renamed.png",
        type: "file",
      });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.error).toMatch(/already exists/i);
  });

  // 15. Directory path
  test("returns 400 when path points to a directory", async () => {
    setupFullMocks();
    mockGithubApiGet.mockResolvedValueOnce([
      { name: "file1.png", type: "file" },
      { name: "file2.png", type: "file" },
    ]);

    const req = createRequest(["overview"], { newName: "renamed-dir" });
    const res = await PATCH(req, { params: createParams(["overview"]) });
    expect(res.status).toBe(400);

    const body = await res.json();
    expect(body.error).toMatch(/directory/i);
  });

  // 16. Happy path — atomic rename via Git Trees API
  test("returns 200 with oldPath, newPath, commitSha on successful rename", async () => {
    setupFullMocks();
    // First GET: old file exists
    // Second GET: new path returns 404 (doesn't exist)
    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      })
      .mockRejectedValueOnce(
        new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/renamed.png", 404),
      )
      .mockResolvedValueOnce({ default_branch: "main" })
      .mockResolvedValueOnce({
        object: { sha: "commitsha000", type: "commit" },
      })
      .mockResolvedValueOnce({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body.oldPath).toBe("knowledge-base/overview/test.png");
    expect(body.newPath).toBe("knowledge-base/overview/renamed.png");
    expect(body.commitSha).toBe("newcommitsha222");

    // Verify Git Trees API call
    expect(mockGithubApiPost).toHaveBeenCalledWith(
      TEST_INSTALLATION_ID,
      "/repos/test-owner/test-repo/git/trees",
      expect.objectContaining({
        base_tree: "treesha000",
        tree: expect.arrayContaining([
          expect.objectContaining({ path: "knowledge-base/overview/test.png", sha: null }),
          expect.objectContaining({ path: "knowledge-base/overview/renamed.png", sha: "blobsha123" }),
        ]),
      }),
    );
  });

  // 17. Workspace sync failure
  test("returns 500 with SYNC_FAILED when git pull fails after rename", async () => {
    setupFullMocks();
    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      })
      .mockRejectedValueOnce(
        new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/renamed.png", 404),
      )
      .mockResolvedValueOnce({ default_branch: "main" })
      .mockResolvedValueOnce({
        object: { sha: "commitsha000", type: "commit" },
      })
      .mockResolvedValueOnce({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });
    mockExecFile.mockRejectedValue(new Error("git pull failed: merge conflict"));

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.code).toBe("SYNC_FAILED");
  });

  // 18. GitHub API error during tree creation
  test("returns 502 when GitHub API fails during tree creation", async () => {
    setupFullMocks();
    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      })
      .mockRejectedValueOnce(
        new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/renamed.png", 404),
      )
      .mockResolvedValueOnce({ default_branch: "main" })
      .mockResolvedValueOnce({
        object: { sha: "commitsha000", type: "commit" },
      })
      .mockResolvedValueOnce({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });
    mockGithubApiPost.mockRejectedValue(
      new MockGitHubApiError("GitHub API request failed: 500 /repos/test-owner/test-repo/git/trees", 500),
    );

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(502);
  });

  // 19. newName that becomes empty after control char stripping
  test("returns 400 for newName that is only control characters", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: "\x01\x02.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 20. newName starting with dot
  test("returns 400 for newName starting with dot", async () => {
    setupFullMocks();

    const req = createRequest(["overview", "test.png"], { newName: ".hidden.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 21. File not on disk (ENOENT) — skip symlink check
  test("skips symlink check when file does not exist locally", async () => {
    setupFullMocks();
    const enoent = new Error("ENOENT: no such file or directory") as NodeJS.ErrnoException;
    enoent.code = "ENOENT";
    mockLstat.mockRejectedValue(enoent);

    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "remote-only.png",
        path: "knowledge-base/overview/remote-only.png",
        type: "file",
      })
      .mockRejectedValueOnce(
        new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/renamed.png", 404),
      )
      .mockResolvedValueOnce({ default_branch: "main" })
      .mockResolvedValueOnce({
        object: { sha: "commitsha000", type: "commit" },
      })
      .mockResolvedValueOnce({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });

    const req = createRequest(["overview", "remote-only.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "remote-only.png"]) });
    expect(res.status).toBe(200);
  });

  // 22. No repo connected
  test("returns 400 when no repository is connected", async () => {
    setupAuthenticatedUser();
    setupUserData({ repo_url: null, github_installation_id: null });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(400);
  });

  // 23. Credential helper cleanup
  test("credential helper is cleaned up after successful rename", async () => {
    setupFullMocks();
    mockGithubApiGet
      .mockResolvedValueOnce({
        sha: "blobsha123",
        name: "test.png",
        path: "knowledge-base/overview/test.png",
        type: "file",
      })
      .mockRejectedValueOnce(
        new MockGitHubApiError("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/overview/renamed.png", 404),
      )
      .mockResolvedValueOnce({ default_branch: "main" })
      .mockResolvedValueOnce({
        object: { sha: "commitsha000", type: "commit" },
      })
      .mockResolvedValueOnce({
        sha: "commitsha000",
        tree: { sha: "treesha000" },
      });

    const req = createRequest(["overview", "test.png"], { newName: "renamed.png" });
    const res = await PATCH(req, { params: createParams(["overview", "test.png"]) });
    expect(res.status).toBe(200);

    expect(mockWriteFileSync).toHaveBeenCalledWith(
      "/tmp/git-cred-test-uuid",
      expect.stringContaining("x-access-token"),
      expect.objectContaining({ mode: 0o700 }),
    );
    expect(mockUnlinkSync).toHaveBeenCalledWith("/tmp/git-cred-test-uuid");
  });
});
